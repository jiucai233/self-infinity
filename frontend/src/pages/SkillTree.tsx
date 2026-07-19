import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import { api } from '../api'
import type { AuditMode, SkillNode } from '../types'

const ONBOARDING_DISMISSED_KEY = 'self-infinity-onboarding-dismissed'

const EXAMPLE_TOPICS = ['B 树', '把这个项目部署上线', '强化学习']

const STATUS_LABEL: Record<SkillNode['status'], string> = {
  locked: '未解锁',
  available: '可审计',
  mastered: '已掌握',
}

const STATUS_COLOR: Record<SkillNode['status'], string> = {
  locked: 'var(--dim)',
  available: 'var(--accent)',
  mastered: '#facc15',
}

const NODE_TYPE_LABEL: Record<SkillNode['node_type'], string> = {
  concept: '概念 · 讲清楚为什么',
  task: '任务 · 做到就行',
}

// No hue to lean on in the mono system, so concept/task stay distinct via
// tag treatment instead of color: concept ("讲清楚为什么") is the lighter
// outlined chip, task ("做到就行") is the heavier filled/inverted chip.
const NODE_TYPE_TAG_CLASS: Record<SkillNode['node_type'], string> = {
  concept: 'tag tag--outline',
  task: 'tag tag--filled',
}

// One connector line for a parent -> child edge, positioned in coordinates
// relative to the tree content wrapper (the element the SVG overlay covers).
interface SkillEdge {
  parentId: number
  childId: number
  d: string
  status: SkillNode['status']
}

// Pixel geometry for the tree diagram. Cards are a fixed width; rows get a
// generous fixed height so variable-length descriptions don't cause
// vertically adjacent rows to visually collide.
const CARD_WIDTH = 220
const COL_WIDTH = 236 // CARD_WIDTH + horizontal gap between sibling columns
const ROW_HEIGHT = 240 // vertical distance between depth levels
const TREE_GAP_SLOTS = 1 // extra empty columns inserted between separate root trees

export interface SkillLayoutPosition {
  x: number
  y: number
}

/**
 * Assigns each node an (x, y) position such that a node's horizontal
 * position is derived from its own subtree, not from "which slot in a flat
 * row" it happens to land in. This app can render several independently
 * generated trees (forests) side by side, so parent_id === null nodes are
 * each treated as the root of their own subtree.
 *
 * Simplified bottom-up centering (in the spirit of Reingold-Tilford, without
 * the contour-fitting complexity):
 *   - leaf nodes get the next available integer column, assigned in
 *     left-to-right (depth-first, array-order) traversal order
 *   - an internal node's column is the mean of its children's columns
 * Because leaves are handed out in strictly increasing order during a single
 * depth-first traversal, every subtree occupies a contiguous, non-overlapping
 * range of columns — so a parent always sits centered over its own children
 * and never drifts into an unrelated cousin subtree's columns.
 *
 * Separate root trees are kept from touching by leaving a gap of
 * TREE_GAP_SLOTS empty columns after each root tree finishes.
 */
export function computeSkillTreeLayout(
  skills: SkillNode[],
): { positions: Map<number, SkillLayoutPosition>; width: number; height: number } {
  const childrenOf = new Map<number, SkillNode[]>()
  for (const s of skills) {
    if (s.parent_id != null) {
      const list = childrenOf.get(s.parent_id) ?? []
      list.push(s)
      childrenOf.set(s.parent_id, list)
    }
  }
  const roots = skills.filter((s) => s.parent_id == null)

  const colOf = new Map<number, number>()
  const depthOf = new Map<number, number>()
  let nextLeafSlot = 0
  let maxDepth = 0

  function assign(node: SkillNode, depth: number): number {
    depthOf.set(node.id, depth)
    maxDepth = Math.max(maxDepth, depth)
    const kids = childrenOf.get(node.id) ?? []
    let col: number
    if (kids.length === 0) {
      col = nextLeafSlot
      nextLeafSlot += 1
    } else {
      const childCols = kids.map((k) => assign(k, depth + 1))
      col = childCols.reduce((a, b) => a + b, 0) / childCols.length
    }
    colOf.set(node.id, col)
    return col
  }

  for (const root of roots) {
    assign(root, 0)
    nextLeafSlot += TREE_GAP_SLOTS
  }

  const positions = new Map<number, SkillLayoutPosition>()
  for (const s of skills) {
    const col = colOf.get(s.id) ?? 0
    const depth = depthOf.get(s.id) ?? 0
    positions.set(s.id, { x: col * COL_WIDTH, y: depth * ROW_HEIGHT })
  }

  const maxCol = Math.max(0, ...Array.from(colOf.values()))
  const width = skills.length > 0 ? maxCol * COL_WIDTH + CARD_WIDTH : 0
  const height = skills.length > 0 ? (maxDepth + 1) * ROW_HEIGHT : 0

  return { positions, width, height }
}

export default function SkillTree({
  onAudit,
}: {
  onAudit: (skillId: number, nodeType: SkillNode['node_type'], mode: AuditMode) => void
}) {
  const [skills, setSkills] = useState<SkillNode[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [topic, setTopic] = useState('')
  const [generating, setGenerating] = useState(false)
  const [auditMode, setAuditMode] = useState<AuditMode>('day')

  // Clarify-first flow: when the clarify endpoint says the topic is too
  // vague, we park the original topic + its questions here and render an
  // inline answer form instead of calling generateTree immediately.
  const [clarifyTopicText, setClarifyTopicText] = useState<string | null>(null)
  const [clarifyQuestions, setClarifyQuestions] = useState<string[]>([])
  const [clarifyAnswers, setClarifyAnswers] = useState<string[]>([])

  const [onboardingDismissed, setOnboardingDismissed] = useState(
    () => window.localStorage.getItem(ONBOARDING_DISMISSED_KEY) === '1',
  )

  // Connector-line overlay: cards register themselves in cardRefs (keyed by
  // skill id) via callback refs, then treeContentRef's descendants are
  // measured to compute one SVG path per parent-child edge. Recomputed after
  // layout (useLayoutEffect) and on any resize/reflow of the tree content.
  const treeContentRef = useRef<HTMLDivElement | null>(null)
  const cardRefs = useRef<Map<number, HTMLDivElement>>(new Map())
  const [edges, setEdges] = useState<SkillEdge[]>([])

  const refresh = () => api.listSkills().then(setSkills).catch((e) => setError(String(e)))

  useEffect(() => {
    refresh().finally(() => setLoading(false))
  }, [])

  useLayoutEffect(() => {
    const recomputeEdges = () => {
      const container = treeContentRef.current
      if (!container) return
      const containerRect = container.getBoundingClientRect()
      const byId = new Map(skills.map((s) => [s.id, s]))
      const next: SkillEdge[] = []
      for (const child of skills) {
        if (child.parent_id == null) continue
        const parent = byId.get(child.parent_id)
        const parentEl = cardRefs.current.get(child.parent_id)
        const childEl = cardRefs.current.get(child.id)
        if (!parent || !parentEl || !childEl) continue
        const pRect = parentEl.getBoundingClientRect()
        const cRect = childEl.getBoundingClientRect()
        const x1 = pRect.left + pRect.width / 2 - containerRect.left
        const y1 = pRect.bottom - containerRect.top
        const x2 = cRect.left + cRect.width / 2 - containerRect.left
        const y2 = cRect.top - containerRect.top
        // Manhattan/stepped orthogonal path — straight down from the
        // parent's bottom-center, straight across at the midpoint row,
        // straight down into the child's top-center. Chunky right angles
        // read as pixel-art circuitry instead of an organic curve.
        const midY = (y1 + y2) / 2
        next.push({
          parentId: parent.id,
          childId: child.id,
          status: child.status,
          d: `M ${x1} ${y1} L ${x1} ${midY} L ${x2} ${midY} L ${x2} ${y2}`,
        })
      }
      setEdges(next)
    }

    recomputeEdges()

    window.addEventListener('resize', recomputeEdges)
    let observer: ResizeObserver | null = null
    if (typeof ResizeObserver !== 'undefined' && treeContentRef.current) {
      observer = new ResizeObserver(recomputeEdges)
      observer.observe(treeContentRef.current)
    }
    return () => {
      window.removeEventListener('resize', recomputeEdges)
      observer?.disconnect()
    }
  }, [skills])

  function dismissOnboarding() {
    window.localStorage.setItem(ONBOARDING_DISMISSED_KEY, '1')
    setOnboardingDismissed(true)
  }

  async function runGenerate(finalTopic: string) {
    setGenerating(true)
    setError(null)
    try {
      await api.generateTree(finalTopic)
      setTopic('')
      setClarifyTopicText(null)
      setClarifyQuestions([])
      setClarifyAnswers([])
      await refresh()
    } catch (e) {
      setError(String(e))
    } finally {
      setGenerating(false)
    }
  }

  async function generate() {
    const trimmed = topic.trim()
    if (!trimmed) return
    setGenerating(true)
    setError(null)
    try {
      const result = await api.clarifyTopic(trimmed)
      if (result.needs_clarification && result.questions.length > 0) {
        setClarifyTopicText(trimmed)
        setClarifyQuestions(result.questions)
        setClarifyAnswers(result.questions.map(() => ''))
        setGenerating(false)
        return
      }
    } catch {
      // Clarify endpoint is best-effort — if it fails, silently fall
      // through and generate straight from the original topic.
    }
    await runGenerate(trimmed)
  }

  function submitClarifyAnswers() {
    if (clarifyTopicText === null) return
    const lines = clarifyQuestions
      .map((q, i) => `- ${q}：${clarifyAnswers[i]?.trim() ?? ''}`)
      .join('\n')
    const combined = `${clarifyTopicText}\n\n补充说明：\n${lines}`
    void runGenerate(combined)
  }

  function skipClarifyAnswers() {
    if (clarifyTopicText === null) return
    void runGenerate(clarifyTopicText)
  }

  if (loading) return <p className="dim">加载技能树…</p>

  const { positions, width, height } = computeSkillTreeLayout(skills)
  const masteredCount = skills.filter((s) => s.status === 'mastered').length

  return (
    <div>
      <h2 className="pixel-font" style={{ fontSize: 18 }}>
        技能树
      </h2>
      <p className="dim" style={{ marginBottom: 16 }}>
        点亮一个「原理方块」，必须先通过费曼审计官的压力测试。学习内容不设限——
        给一个主题或一个想完成的大任务，规划官会拆成小节点接到树上。
      </p>

      {!onboardingDismissed && (
        <div className="panel" style={{ marginBottom: 16, borderColor: 'var(--accent)' }}>
          <p style={{ marginBottom: 6, fontWeight: 600 }}>怎么玩？</p>
          <p className="dim" style={{ fontSize: 13, lineHeight: 1.7, marginBottom: 10 }}>
            ① 输入一个主题或想完成的任务，AI 会拆成一棵技能树
            <br />
            ② 每个节点必须先通过审计官的追问才能点亮
            <br />
            ③ 概念型追问到第一性原理，任务型只看是否做到
            <br />
            ④ 审计失败会强制你反思，蒸馏成可复用的原则
          </p>
          <button className="accent" onClick={dismissOnboarding}>
            知道了
          </button>
        </div>
      )}

      <div
        className="panel"
        style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 16 }}
      >
        <span style={{ fontSize: 12 }}>审计模式：</span>
        <button
          className={auditMode === 'day' ? 'accent' : undefined}
          onClick={() => setAuditMode('day')}
        >
          白天（标准）
        </button>
        <button
          className={auditMode === 'night' ? 'accent' : undefined}
          onClick={() => setAuditMode('night')}
        >
          夜晚（深度）
        </button>
        <span className="dim" style={{ fontSize: 11 }}>
          夜晚模式追问轮数翻倍，适合难啃的硬骨头话题
        </span>
      </div>

      <div className="panel" style={{ marginBottom: 24 }}>
        <div style={{ display: 'flex', gap: 8 }}>
          <input
            value={topic}
            placeholder="例如：B 树 / 把这个项目上线所需要的知识"
            onChange={(e) => setTopic(e.target.value)}
            disabled={generating || clarifyQuestions.length > 0}
            onKeyDown={(e) => e.key === 'Enter' && generate()}
          />
          <button
            className="accent"
            onClick={generate}
            disabled={generating || !topic.trim() || clarifyQuestions.length > 0}
          >
            {generating ? '规划官拆解中…' : '生成技能树'}
          </button>
        </div>

        <div style={{ display: 'flex', gap: 6, marginTop: 10, flexWrap: 'wrap' }}>
          <span className="dim" style={{ fontSize: 11 }}>
            没想法？试试：
          </span>
          {EXAMPLE_TOPICS.map((example) => (
            <span
              key={example}
              className="tag"
              role="button"
              tabIndex={0}
              onClick={() => setTopic(example)}
              style={{ cursor: 'pointer' }}
            >
              {example}
            </span>
          ))}
        </div>

        {clarifyQuestions.length > 0 && (
          <div style={{ marginTop: 16, borderTop: '1px solid var(--border)', paddingTop: 16 }}>
            <p style={{ fontSize: 13, marginBottom: 10 }}>
              这个主题有点大，先回答一两个问题帮你缩小范围（也可以跳过）：
            </p>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginBottom: 12 }}>
              {clarifyQuestions.map((q, i) => (
                <div key={i}>
                  <label
                    htmlFor={`clarify-answer-${i}`}
                    className="dim"
                    style={{ fontSize: 12, display: 'block', marginBottom: 4 }}
                  >
                    {q}
                  </label>
                  <input
                    id={`clarify-answer-${i}`}
                    value={clarifyAnswers[i] ?? ''}
                    disabled={generating}
                    onChange={(e) =>
                      setClarifyAnswers((prev) => {
                        const next = [...prev]
                        next[i] = e.target.value
                        return next
                      })
                    }
                  />
                </div>
              ))}
            </div>
            <div style={{ display: 'flex', gap: 8 }}>
              <button className="accent" onClick={submitClarifyAnswers} disabled={generating}>
                {generating ? '规划官拆解中…' : '生成'}
              </button>
              <button onClick={skipClarifyAnswers} disabled={generating}>
                跳过，直接生成
              </button>
            </div>
          </div>
        )}
      </div>

      {error && <p style={{ color: 'var(--danger)', marginBottom: 16 }}>{error}</p>}

      {skills.length > 0 && (
        <div className="skilltree-stat-pills">
          <div className="stat-pill pixel-border">
            <span className="dim stat-pill-label">已掌握</span>
            <span className="pixel-font stat-pill-value">
              {masteredCount} / {skills.length}
            </span>
          </div>
        </div>
      )}

      <div className="pixel-grid" style={{ overflowX: 'auto', position: 'relative' }}>
        <div
          ref={treeContentRef}
          style={{ position: 'relative', width, height, minWidth: '100%' }}
        >
          <svg
            style={{
              position: 'absolute',
              inset: 0,
              width: '100%',
              height: '100%',
              pointerEvents: 'none',
              zIndex: 0,
              overflow: 'visible',
            }}
          >
            {edges.map((edge) => (
              <path
                key={`${edge.parentId}-${edge.childId}`}
                data-testid={`skill-edge-${edge.parentId}-${edge.childId}`}
                d={edge.d}
                className={
                  edge.status === 'locked'
                    ? 'skill-edge skill-edge--locked'
                    : 'skill-edge skill-edge--active'
                }
              />
            ))}
          </svg>

          {skills.map((skill) => {
            const pos = positions.get(skill.id) ?? { x: 0, y: 0 }
            return (
              <div
                key={skill.id}
                ref={(el) => {
                  if (el) cardRefs.current.set(skill.id, el)
                  else cardRefs.current.delete(skill.id)
                }}
                className="panel"
                style={{
                  position: 'absolute',
                  left: pos.x,
                  top: pos.y,
                  width: CARD_WIDTH,
                  zIndex: 1,
                  opacity: skill.status === 'locked' ? 0.5 : 1,
                }}
              >
                <div
                  style={{
                    width: 32,
                    height: 32,
                    background:
                      skill.status === 'mastered' ? STATUS_COLOR.mastered : 'var(--bg)',
                    border: `2px solid ${STATUS_COLOR[skill.status]}`,
                    borderRadius: 0,
                    marginBottom: 8,
                  }}
                />
                <h3 className="pixel-font" style={{ fontSize: 12, lineHeight: 1.6 }}>
                  {skill.title}
                </h3>
                <span
                  className={NODE_TYPE_TAG_CLASS[skill.node_type]}
                  style={{ marginBottom: 6 }}
                >
                  {NODE_TYPE_LABEL[skill.node_type]}
                </span>
                <div style={{ marginBottom: 2 }} />
                <p className="dim" style={{ fontSize: 12, marginBottom: 8 }}>
                  {skill.description}
                </p>
                <p style={{ fontSize: 12, color: STATUS_COLOR[skill.status], marginBottom: 8 }}>
                  {STATUS_LABEL[skill.status]}
                  {skill.mastery_score != null ? ` · ${skill.mastery_score}分` : ''}
                </p>
                <button
                  className={skill.status === 'available' ? 'accent' : undefined}
                  disabled={skill.status !== 'available'}
                  onClick={() => onAudit(skill.id, skill.node_type, auditMode)}
                >
                  {skill.status === 'mastered' ? '已通过审计' : '发起审计'}
                </button>
              </div>
            )
          })}
        </div>
      </div>
    </div>
  )
}
