import { useEffect, useState } from 'react'
import { api } from '../api'
import type { AuditMode, SkillNode } from '../types'

const NODE_TYPE_LABEL: Record<SkillNode['node_type'], string> = {
  concept: 'Concept Node',
  task: 'Task Node',
}

// Per skill_node_detail_pixel_mono_white/screen.png's bottom stat row —
// only "Unlocked Nodes" is real (same mastered/total count as the tree
// hub's stat pill); the other two slots don't have a backing numeric
// system in this app, so they're clearly-decorative flavor rather than
// fabricated-but-plausible numbers, kept to pad out the row per the
// template's 3-4 box layout.
function StatBox({ label, value }: { label: string; value: string }) {
  return (
    <div className="panel stat-card">
      <span className="dim pixel-font stat-card-label">{label}</span>
      <span className="pixel-font stat-card-value">{value}</span>
    </div>
  )
}

export default function SkillNodeDetail({
  skillId,
  onBack,
  onAudit,
}: {
  skillId: number
  onBack: () => void
  onAudit: (skillId: number, nodeType: SkillNode['node_type'], mode: AuditMode) => void
}) {
  const [skills, setSkills] = useState<SkillNode[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    api
      .listSkills()
      .then(setSkills)
      .catch((e) => setError(String(e)))
      .finally(() => setLoading(false))
  }, [])

  if (loading) return <p className="dim">Loading node…</p>
  if (error) return <p style={{ color: 'var(--danger)' }}>{error}</p>

  const skill = skills.find((s) => s.id === skillId)
  if (!skill) return <p className="dim">Node not found.</p>

  const parent = skill.parent_id != null ? skills.find((s) => s.id === skill.parent_id) : null
  const masteredCount = skills.filter((s) => s.status === 'mastered').length
  const progressionPct = skill.status === 'mastered' ? (skill.mastery_score ?? 100) : 0

  return (
    <div>
      <p className="dim pixel-font" style={{ fontSize: 10, marginBottom: 16 }}>
        <span
          role="button"
          tabIndex={0}
          onClick={onBack}
          onKeyDown={(e) => e.key === 'Enter' && onBack()}
          style={{ cursor: 'pointer', textDecoration: 'underline' }}
        >
          Skills
        </span>
        {' > NODE DETAIL'}
      </p>

      <div className="panel" style={{ marginBottom: 16 }}>
        <h2 className="pixel-font" style={{ fontSize: 16, marginBottom: 6 }}>
          {skill.title}
        </h2>
        <p className="dim" style={{ fontSize: 12, marginBottom: 12 }}>
          {NODE_TYPE_LABEL[skill.node_type]}
        </p>
        <p style={{ fontSize: 13 }}>{skill.description}</p>
      </div>

      <div className="panel" style={{ marginBottom: 16 }}>
        <p className="dim pixel-font" style={{ fontSize: 10, marginBottom: 8 }}>
          PROGRESSION
        </p>
        <div
          style={{
            width: '100%',
            height: 12,
            border: '1px solid var(--border-strong)',
            marginBottom: 6,
          }}
        >
          <div
            style={{
              width: `${progressionPct}%`,
              height: '100%',
              background: skill.status === 'mastered' ? '#facc15' : 'var(--accent)',
            }}
          />
        </div>
        <p className="dim" style={{ fontSize: 12 }}>
          {Math.round(progressionPct)}%
        </p>
      </div>

      <div
        style={{
          display: 'grid',
          gridTemplateColumns: '1fr 1fr',
          gap: 16,
          marginBottom: 16,
        }}
      >
        <div className="panel">
          <p className="dim pixel-font" style={{ fontSize: 10, marginBottom: 8 }}>
            REQUIREMENTS
          </p>
          {/* real: derived from the node's actual parent_id, not fabricated
              prerequisite text. */}
          <p style={{ fontSize: 13 }}>
            {parent ? `Requires: ${parent.title}` : 'No prerequisites'}
          </p>
        </div>
        <div className="panel">
          <p className="dim pixel-font" style={{ fontSize: 10, marginBottom: 8 }}>
            BENEFITS
          </p>
          {/* decorative: no numeric buff system backs these — flavor lines
              standing in for the template's "+15% Action Speed" chips. */}
          <p style={{ fontSize: 13, marginBottom: 4 }}>+Understanding</p>
          <p style={{ fontSize: 13 }}>+Progress toward mastery</p>
        </div>
      </div>

      <div className="panel" style={{ marginBottom: 16 }}>
        <button
          className={skill.status === 'available' ? 'accent' : undefined}
          disabled={skill.status !== 'available'}
          onClick={() => onAudit(skill.id, skill.node_type, 'day')}
        >
          {skill.status === 'mastered'
            ? 'Mastered'
            : skill.status === 'locked'
              ? 'Locked'
              : 'Allocate Skill Point'}
        </button>
      </div>

      <div className="avatar-stat-row">
        <StatBox label="UNLOCKED NODES" value={`${masteredCount} / ${skills.length}`} />
        {/* decorative: no ranking/playtime tracking exists in this app —
            static flavor values, not derived from anything real. */}
        <StatBox label="GLOBAL RANK" value="#128" />
        <StatBox label="TIME PLAYED" value="12H 40M" />
      </div>
    </div>
  )
}
