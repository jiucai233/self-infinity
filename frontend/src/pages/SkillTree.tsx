import { useEffect, useState } from 'react'
import { api } from '../api'
import type { AuditMode, SkillNode } from '../types'

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

const NODE_TYPE_TAG_STYLE: Record<SkillNode['node_type'], { bg: string; color: string }> = {
  concept: { bg: 'var(--accent-tag-bg)', color: 'var(--accent-strong)' },
  task: { bg: 'var(--info-tag-bg)', color: 'var(--info-strong)' },
}

function buildLevels(skills: SkillNode[]): SkillNode[][] {
  const byParent = new Map<number | null, SkillNode[]>()
  for (const s of skills) {
    const list = byParent.get(s.parent_id) ?? []
    list.push(s)
    byParent.set(s.parent_id, list)
  }
  const levels: SkillNode[][] = []
  let frontier = byParent.get(null) ?? []
  while (frontier.length > 0) {
    levels.push(frontier)
    const next: SkillNode[] = []
    for (const node of frontier) {
      next.push(...(byParent.get(node.id) ?? []))
    }
    frontier = next
  }
  return levels
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

  const refresh = () => api.listSkills().then(setSkills).catch((e) => setError(String(e)))

  useEffect(() => {
    refresh().finally(() => setLoading(false))
  }, [])

  async function generate() {
    if (!topic.trim()) return
    setGenerating(true)
    setError(null)
    try {
      await api.generateTree(topic.trim())
      setTopic('')
      await refresh()
    } catch (e) {
      setError(String(e))
    } finally {
      setGenerating(false)
    }
  }

  if (loading) return <p className="dim">加载技能树…</p>

  const levels = buildLevels(skills)

  return (
    <div>
      <h2>技能树</h2>
      <p className="dim" style={{ marginBottom: 16 }}>
        点亮一个「原理方块」，必须先通过费曼审计官的压力测试。学习内容不设限——
        给一个主题或一个想完成的大任务，规划官会拆成小节点接到树上。
      </p>

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

      <div className="panel" style={{ display: 'flex', gap: 8, marginBottom: 24 }}>
        <input
          value={topic}
          placeholder="例如：B 树 / 把这个项目上线所需要的知识"
          onChange={(e) => setTopic(e.target.value)}
          disabled={generating}
          onKeyDown={(e) => e.key === 'Enter' && generate()}
        />
        <button className="accent" onClick={generate} disabled={generating || !topic.trim()}>
          {generating ? '规划官拆解中…' : '生成技能树'}
        </button>
      </div>

      {error && <p style={{ color: 'var(--danger)', marginBottom: 16 }}>{error}</p>}

      <div style={{ display: 'flex', flexDirection: 'column', gap: 32 }}>
        {levels.map((level, i) => (
          <div key={i} style={{ display: 'flex', gap: 16, flexWrap: 'wrap' }}>
            {level.map((skill) => (
              <div
                key={skill.id}
                className="panel"
                style={{
                  width: 220,
                  opacity: skill.status === 'locked' ? 0.5 : 1,
                }}
              >
                <div
                  style={{
                    width: 32,
                    height: 32,
                    background:
                      skill.status === 'mastered' ? STATUS_COLOR.mastered : 'var(--bg)',
                    border: `1px solid ${STATUS_COLOR[skill.status]}`,
                    borderRadius: 4,
                    marginBottom: 8,
                  }}
                />
                <h3 style={{ fontSize: 15 }}>{skill.title}</h3>
                <span
                  className="tag"
                  style={{
                    marginBottom: 6,
                    background: NODE_TYPE_TAG_STYLE[skill.node_type].bg,
                    color: NODE_TYPE_TAG_STYLE[skill.node_type].color,
                  }}
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
            ))}
          </div>
        ))}
      </div>
    </div>
  )
}
