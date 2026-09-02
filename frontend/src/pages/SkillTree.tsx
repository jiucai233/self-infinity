import { useEffect, useMemo, useState } from 'react'
import { api } from '../api'
import KnowledgeGraph from './KnowledgeGraph'
import type {
  AuditMode,
  CourseDifficulty,
  CourseOptions,
  CourseSource,
  DifficultyTier,
  GraphResponse,
  RecommendationResponse,
  SkillNode,
} from '../types'

const TIER_LABEL: Record<DifficultyTier, string> = {
  easy: 'Easy',
  medium: 'Medium',
  hard: 'Hard',
}

const ONBOARDING_DISMISSED_KEY = 'self-infinity-onboarding-dismissed'

const EXAMPLE_TOPICS = ['B-trees', 'Deploy this project', 'Reinforcement learning']

const STATUS_LABEL: Record<SkillNode['status'], string> = {
  locked: 'Locked',
  available: 'Available',
  mastered: 'Mastered',
}

const STATUS_COLOR: Record<SkillNode['status'], string> = {
  locked: 'var(--dim)',
  available: 'var(--accent)',
  mastered: '#facc15',
}

const NODE_TYPE_LABEL: Record<SkillNode['node_type'], string> = {
  concept: 'Concept · Explain the why',
  task: 'Task · Just get it done',
}

// No hue to lean on in the mono system, so concept/task stay distinct via
// tag treatment instead of color: concept ("explain the why") is the lighter
// outlined chip, task ("just get it done") is the heavier filled/inverted chip.
const NODE_TYPE_TAG_CLASS: Record<SkillNode['node_type'], string> = {
  concept: 'tag tag--outline',
  task: 'tag tag--filled',
}

const NEAREST_NEIGHBOR_COUNT = 3

// Undirected adjacency built from the graph's edges — a node's neighbors are
// anyone connected via parent/origin/related, regardless of which side is
// source/target. Used only for the "nearest N nodes" lookup below. The tree
// canvas that used to render this data as an absolutely-positioned diagram
// (computeSkillTreeLayout + Manhattan SVG connectors) has been retired per
// explicit user feedback ("那个树的话也别干了") in favor of this
// recommendation list — the underlying parent_id graph structure is
// unchanged, only the visualization went away.
function buildAdjacency(edges: GraphResponse['edges']): Map<string, string[]> {
  const adjacency = new Map<string, string[]>()
  const link = (a: string, b: string) => {
    const list = adjacency.get(a) ?? []
    list.push(b)
    adjacency.set(a, list)
  }
  for (const e of edges) {
    link(e.source, e.target)
    link(e.target, e.source)
  }
  return adjacency
}

// BFS outward from `startId`, collecting the first `limit` distinct nodes
// encountered (breadth order = closest first), skipping the start node
// itself. Returns fewer than `limit` entries for small/isolated subtrees —
// no padding with fake neighbors.
function nearestNeighbors(
  adjacency: Map<string, string[]>,
  nodesById: Map<string, GraphResponse['nodes'][number]>,
  startId: string,
  limit: number,
): GraphResponse['nodes'] {
  const visited = new Set<string>([startId])
  const queue: string[] = [...(adjacency.get(startId) ?? [])]
  const result: GraphResponse['nodes'] = []
  let i = 0
  while (i < queue.length && result.length < limit) {
    const id = queue[i]
    i += 1
    if (visited.has(id)) continue
    visited.add(id)
    const node = nodesById.get(id)
    if (node) result.push(node)
    if (result.length >= limit) break
    for (const next of adjacency.get(id) ?? []) {
      if (!visited.has(next)) queue.push(next)
    }
  }
  return result
}

export default function SkillTree({
  onAudit,
  onOpenDetail,
}: {
  onAudit: (skillId: number, nodeType: SkillNode['node_type'], mode: AuditMode) => void
  onOpenDetail?: (skillId: number) => void
}) {
  const [skills, setSkills] = useState<SkillNode[]>([])
  const [graph, setGraph] = useState<GraphResponse | null>(null)
  const [recommendation, setRecommendation] = useState<RecommendationResponse | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [topic, setTopic] = useState('')
  const [generating, setGenerating] = useState(false)
  // Course shape knobs handed to the Planner. Defaults mirror the backend's
  // (12 / 4 / standard) so an untouched form behaves exactly as before.
  const [course, setCourse] = useState<CourseOptions>({
    node_count: 12,
    max_depth: 4,
    difficulty: 'standard',
    search_syllabus: true,
  })
  // Which real course the last generated tree was modelled on, if any. Shown
  // so the structure can be checked against its source — and left empty when
  // there wasn't one, rather than hinting vaguely at provenance.
  const [source, setSource] = useState<CourseSource | null>(null)
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

  const refresh = () =>
    Promise.all([api.listSkills(), api.getGraph()])
      .then(([s, g]) => {
        setSkills(s)
        setGraph(g)
      })
      .catch((e) => setError(String(e)))

  // Separate, best-effort fetch: the bandit recommendation (whitepaper §4.4
  // V2.1) is a nice-to-have steer, not core data the page depends on, so a
  // failure here shouldn't block skills/graph from loading or surface an
  // error banner of its own.
  const refreshRecommendation = () =>
    api
      .getRecommendation()
      .then(setRecommendation)
      .catch(() => setRecommendation(null))

  useEffect(() => {
    refresh().finally(() => setLoading(false))
    refreshRecommendation()
  }, [])

  function dismissOnboarding() {
    window.localStorage.setItem(ONBOARDING_DISMISSED_KEY, '1')
    setOnboardingDismissed(true)
  }

  async function runGenerate(finalTopic: string) {
    setGenerating(true)
    setError(null)
    try {
      const generated = await api.generateTree(finalTopic, course)
      setSource(generated.source)
      setTopic('')
      setClarifyTopicText(null)
      setClarifyQuestions([])
      setClarifyAnswers([])
      await refresh()
      refreshRecommendation()
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
      .map((q, i) => `- ${q}: ${clarifyAnswers[i]?.trim() ?? ''}`)
      .join('\n')
    const combined = `${clarifyTopicText}\n\nAdditional details:\n${lines}`
    void runGenerate(combined)
  }

  function skipClarifyAnswers() {
    if (clarifyTopicText === null) return
    void runGenerate(clarifyTopicText)
  }

  const masteredCount = skills.filter((s) => s.status === 'mastered').length
  // decorative: no real currency system exists — Essence is a flavor stat
  // derived from the real mastered-node count, per the template's
  // "ESSENCE" stat pill next to the real "Mastered X / Y" pill.
  const essence = masteredCount * 25

  // Recommended-next list: only real "available" nodes (unlocked, not yet
  // mastered — locked nodes aren't actionable yet, mastered ones are done).
  // Primary ranking is real direct-child count (higher unlock leverage
  // first); nodes matching the bandit's suggested difficulty tier (§4.4
  // V2.1 — derived from recent pass rate/abandon rate/session length, see
  // backend/app/services/bandit.py) are stably floated to the front of that
  // ranking, not re-scored — this is a nudge toward "reachable difficulty",
  // not a replacement for the leverage-based order.
  const recommendations = useMemo(() => {
    const childCount = new Map<number, number>()
    for (const s of skills) {
      if (s.parent_id != null) childCount.set(s.parent_id, (childCount.get(s.parent_id) ?? 0) + 1)
    }
    const suggestedTier = recommendation?.suggested_tier
    const tiers = recommendation?.skill_tiers
    const matchesSuggestion = (id: number) =>
      suggestedTier != null && tiers?.[String(id)] === suggestedTier
    return skills
      .filter((s) => s.status === 'available')
      .sort(
        (a, b) =>
          Number(matchesSuggestion(b.id)) - Number(matchesSuggestion(a.id)) ||
          (childCount.get(b.id) ?? 0) - (childCount.get(a.id) ?? 0) ||
          a.id - b.id,
      )
  }, [skills, recommendation])

  const adjacency = useMemo(() => (graph ? buildAdjacency(graph.edges) : new Map()), [graph])
  const nodesById = useMemo(
    () => (graph ? new Map(graph.nodes.map((n) => [n.id, n])) : new Map()),
    [graph],
  )

  if (loading) return <p className="dim">Loading skills…</p>

  return (
    <div>
      <h2 className="pixel-font" style={{ fontSize: 18 }}>
        Skills
      </h2>
      <p className="dim" style={{ marginBottom: 16 }}>
        Light up a Principle Block by passing the Feynman Auditor's stress test first. Learning
        isn't scoped — give a topic or a big goal you want to finish, and the Planner will break
        it into small nodes on the tree.
      </p>

      {!onboardingDismissed && (
        <div className="panel" style={{ marginBottom: 16, borderColor: 'var(--accent)' }}>
          <p style={{ marginBottom: 6, fontWeight: 600 }}>How to Play</p>
          <p className="dim" style={{ fontSize: 13, lineHeight: 1.7, marginBottom: 10 }}>
            ① Enter a topic or a task you want to finish — AI breaks it into a skill tree
            <br />
            ② Every node must survive the Auditor's follow-up questions before it lights up
            <br />
            ③ Concept nodes get grilled down to first principles; task nodes just need proof you
            did it
            <br />
            ④ Failing an audit forces a reflection, distilled into a reusable principle
          </p>
          <button className="accent" onClick={dismissOnboarding}>
            Got it
          </button>
        </div>
      )}

      <div
        className="panel"
        style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 16 }}
      >
        <span style={{ fontSize: 12 }}>Audit Mode:</span>
        <button
          className={auditMode === 'day' ? 'accent' : undefined}
          onClick={() => setAuditMode('day')}
        >
          Day (Standard)
        </button>
        <button
          className={auditMode === 'night' ? 'accent' : undefined}
          onClick={() => setAuditMode('night')}
        >
          Night (Deep)
        </button>
        <span className="dim" style={{ fontSize: 11 }}>
          Night mode doubles the safety-ceiling round count — good for the hard stuff. Either way
          the Auditor decides when it's done, not a fixed quota.
        </span>
      </div>

      <div className="panel" style={{ marginBottom: 24 }}>
        <div style={{ display: 'flex', gap: 8 }}>
          <input
            value={topic}
            placeholder="e.g. B-trees / everything needed to ship this project"
            onChange={(e) => setTopic(e.target.value)}
            disabled={generating || clarifyQuestions.length > 0}
            onKeyDown={(e) => e.key === 'Enter' && generate()}
          />
          <button
            className="accent"
            onClick={generate}
            disabled={generating || !topic.trim() || clarifyQuestions.length > 0}
          >
            {generating ? 'Planner is breaking it down…' : 'New Mission'}
          </button>
        </div>

        <div
          style={{ display: 'flex', gap: 14, marginTop: 12, flexWrap: 'wrap', alignItems: 'center' }}
        >
          <label className="dim" style={{ fontSize: 11, display: 'flex', alignItems: 'center', gap: 6 }}>
            Depth
            <select
              value={course.difficulty}
              disabled={generating}
              onChange={(e) =>
                setCourse((c) => ({ ...c, difficulty: e.target.value as CourseDifficulty }))
              }
            >
              <option value="intro">intro — what and why</option>
              <option value="standard">standard — concrete methods</option>
              <option value="deep">deep — named models</option>
            </select>
          </label>

          <label className="dim" style={{ fontSize: 11, display: 'flex', alignItems: 'center', gap: 6 }}>
            <input
              type="checkbox"
              checked={course.search_syllabus}
              disabled={generating}
              onChange={(e) => setCourse((c) => ({ ...c, search_syllabus: e.target.checked }))}
            />
            Look for a real syllabus
          </label>

          <label className="dim" style={{ fontSize: 11, display: 'flex', alignItems: 'center', gap: 6 }}>
            Nodes
            <input
              type="number"
              min={4}
              max={30}
              value={course.node_count}
              disabled={generating}
              style={{ width: 64 }}
              onChange={(e) => setCourse((c) => ({ ...c, node_count: Number(e.target.value) }))}
            />
          </label>

          <label className="dim" style={{ fontSize: 11, display: 'flex', alignItems: 'center', gap: 6 }}>
            Levels
            <input
              type="number"
              min={2}
              max={6}
              value={course.max_depth}
              disabled={generating}
              style={{ width: 56 }}
              onChange={(e) => setCourse((c) => ({ ...c, max_depth: Number(e.target.value) }))}
            />
          </label>
        </div>

        {source && (
          <p className="dim" style={{ fontSize: 11, marginTop: 10, marginBottom: 0 }}>
            Structure modelled on{' '}
            <a href={source.url} target="_blank" rel="noreferrer">
              {source.course}
            </a>{' '}
            — topics only, so you can check it against the real course.
          </p>
        )}

        <div style={{ display: 'flex', gap: 6, marginTop: 10, flexWrap: 'wrap' }}>
          <span className="dim" style={{ fontSize: 11 }}>
            No ideas? Try:
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
              This topic is pretty broad — answer a question or two to narrow it down (optional):
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
                {generating ? 'Planner is breaking it down…' : 'Generate'}
              </button>
              <button onClick={skipClarifyAnswers} disabled={generating}>
                Skip, generate anyway
              </button>
            </div>
          </div>
        )}
      </div>

      {error && <p style={{ color: 'var(--danger)', marginBottom: 16 }}>{error}</p>}

      {skills.length > 0 && (
        <div className="skilltree-stat-pills">
          <div className="stat-pill pixel-border">
            <span className="dim stat-pill-label">Mastered</span>
            <span className="pixel-font stat-pill-value">
              {masteredCount} / {skills.length}
            </span>
          </div>
          <div className="stat-pill pixel-border">
            <span className="dim stat-pill-label">Essence</span>
            <span className="pixel-font stat-pill-value">{essence}</span>
          </div>
        </div>
      )}

      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'minmax(0, 1fr) 420px',
          gap: 24,
          alignItems: 'start',
        }}
      >
        <div style={{ minWidth: 0 }}>
          <h3 className="pixel-font" style={{ fontSize: 13, marginBottom: 8 }}>
            Recommended Next
          </h3>

          {recommendation && (
            <p className="dim" style={{ fontSize: 11, marginBottom: 8 }}>
              Based on your recent audits, {TIER_LABEL[recommendation.suggested_tier].toLowerCase()}{' '}
              nodes are probably the best fit right now — those are pinned to the top, marked{' '}
              <span className="tag tag--outline" style={{ fontSize: 10 }}>
                Suggested
              </span>
              .
            </p>
          )}

          {skills.length === 0 ? (
            <p className="dim">No skills yet — generate one above to get started.</p>
          ) : recommendations.length === 0 ? (
            <p className="dim">
              Nothing available right now — everything's either locked or already mastered.
            </p>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              {recommendations.map((skill) => {
                const neighbors = nearestNeighbors(
                  adjacency,
                  nodesById,
                  `skill-${skill.id}`,
                  NEAREST_NEIGHBOR_COUNT,
                )
                return (
                  <div key={skill.id} className="panel">
                    <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12 }}>
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <h3 className="pixel-font" style={{ fontSize: 13, marginBottom: 6 }}>
                          {skill.title}
                        </h3>
                        <span className={NODE_TYPE_TAG_CLASS[skill.node_type]}>
                          {NODE_TYPE_LABEL[skill.node_type]}
                        </span>
                        {recommendation != null &&
                          recommendation.skill_tiers[String(skill.id)] ===
                            recommendation.suggested_tier && (
                            <span className="tag tag--outline" style={{ marginLeft: 6 }}>
                              Suggested
                            </span>
                          )}
                        <p className="dim" style={{ fontSize: 12, marginTop: 8 }}>
                          {skill.description}
                        </p>
                        <p
                          style={{ fontSize: 12, color: STATUS_COLOR[skill.status], marginTop: 6 }}
                        >
                          {STATUS_LABEL[skill.status]}
                        </p>
                      </div>
                      <div
                        style={{
                          display: 'flex',
                          flexDirection: 'column',
                          gap: 6,
                          flexShrink: 0,
                        }}
                      >
                        <button
                          className="accent"
                          onClick={() => onAudit(skill.id, skill.node_type, auditMode)}
                        >
                          Start Audit
                        </button>
                        {onOpenDetail && (
                          <button onClick={() => onOpenDetail(skill.id)}>Details</button>
                        )}
                      </div>
                    </div>

                    {neighbors.length > 0 && (
                      <div
                        style={{
                          marginTop: 12,
                          paddingTop: 12,
                          borderTop: '1px solid var(--border)',
                          display: 'flex',
                          gap: 8,
                          alignItems: 'center',
                          flexWrap: 'wrap',
                        }}
                      >
                        <span className="dim" style={{ fontSize: 11 }}>
                          Nearest in graph:
                        </span>
                        {neighbors.map((n) => (
                          <span
                            key={n.id}
                            className={n.kind === 'skill' ? 'tag tag--outline' : 'tag'}
                            role={n.kind === 'skill' && onOpenDetail ? 'button' : undefined}
                            tabIndex={n.kind === 'skill' && onOpenDetail ? 0 : undefined}
                            onClick={
                              n.kind === 'skill' && onOpenDetail
                                ? () => onOpenDetail(Number(n.id.replace('skill-', '')))
                                : undefined
                            }
                            style={
                              n.kind === 'skill' && onOpenDetail
                                ? { cursor: 'pointer' }
                                : undefined
                            }
                            title={n.kind === 'principle' ? 'Archive principle' : undefined}
                          >
                            {n.title.length > 20 ? `${n.title.slice(0, 20)}…` : n.title}
                          </span>
                        ))}
                      </div>
                    )}
                  </div>
                )
              })}
            </div>
          )}
        </div>

        <div style={{ position: 'sticky', top: 16 }}>
          <KnowledgeGraph
            compact
            width={420}
            height={520}
            onOpenSkill={(skillId) => onOpenDetail?.(skillId)}
          />
        </div>
      </div>
    </div>
  )
}
