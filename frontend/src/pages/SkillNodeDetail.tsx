import { useEffect, useState } from 'react'
import { api } from '../api'
import { AvatarPortrait, useVitalityFocus } from '../components/Avatar'
import type { AuditMode, SkillNode } from '../types'

const NODE_TYPE_LABEL: Record<SkillNode['node_type'], string> = {
  concept: 'Concept Node',
  task: 'Task Node',
}

const STATUS_LABEL: Record<SkillNode['status'], string> = {
  locked: 'Locked',
  available: 'Available',
  mastered: 'Mastered',
}

// Per skill_node_detail_pixel_mono_white/screen.png's bottom stat row —
// only "Unlocked Nodes" is real (same mastered/total count as the tree
// hub's stat pill); the other two slots don't have a backing numeric
// system in this app, so they're clearly-decorative flavor rather than
// fabricated-but-plausible numbers, kept to pad out the row per the
// template's 4-box layout.
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
  const { focus, loaded } = useVitalityFocus()

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
  const children = skills.filter((s) => s.parent_id === skill.id)
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

      {/* Two-column layout, mirroring
          skill_node_detail_pixel_mono_white/screen.png exactly: a
          portrait+flavor-quote card on the left, and on the right a single
          ability card (title/subtitle/progression together in one box),
          then a REQUIREMENTS/BENEFITS pair, then a combined
          available-points + allocate-button box. Bottom stat row spans
          the full width below both columns. */}
      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'minmax(220px, 1fr) 2fr',
          gap: 16,
          marginBottom: 16,
          alignItems: 'start',
        }}
      >
        <div className="panel">
          <AvatarPortrait focus={focus} loaded={loaded} />
          <div className="pixel-border" style={{ padding: 12, marginTop: 16 }}>
            <p className="dim" style={{ fontSize: 12, fontStyle: 'italic' }}>
              &ldquo;{skill.description}&rdquo;
            </p>
          </div>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          <div className="panel">
            <div
              style={{
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'flex-start',
                marginBottom: 20,
              }}
            >
              <div>
                <h2 className="pixel-font" style={{ fontSize: 18, marginBottom: 8 }}>
                  {skill.title}
                </h2>
                <p className="dim" style={{ fontSize: 12 }}>
                  {/* real: node type + current status, in place of the
                      template's fabricated "ACTIVE ABILITY / LEVEL 3". */}
                  {NODE_TYPE_LABEL[skill.node_type]} / {STATUS_LABEL[skill.status]}
                </p>
              </div>
              <div className="pixel-border" style={{ width: 40, height: 40, flexShrink: 0 }} />
            </div>

            <div
              style={{
                display: 'flex',
                justifyContent: 'space-between',
                marginBottom: 8,
              }}
            >
              <p className="dim pixel-font" style={{ fontSize: 10 }}>
                PROGRESSION
              </p>
              <p className="pixel-font" style={{ fontSize: 12 }}>
                {Math.round(progressionPct)}%
              </p>
            </div>
            <div
              style={{
                width: '100%',
                height: 12,
                border: '1px solid var(--border-strong)',
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
          </div>

          <div
            style={{
              display: 'grid',
              gridTemplateColumns: '1fr 1fr',
              gap: 16,
            }}
          >
            <div className="panel">
              <p className="dim pixel-font" style={{ fontSize: 10, marginBottom: 8 }}>
                REQUIREMENTS
              </p>
              {/* real: derived from the node's actual parent_id, not
                  fabricated prerequisite text. */}
              <p style={{ fontSize: 13 }}>
                {parent ? `Requires: ${parent.title}` : 'No prerequisites'}
              </p>
            </div>
            <div className="panel">
              <p className="dim pixel-font" style={{ fontSize: 10, marginBottom: 8 }}>
                BENEFITS
              </p>
              {/* real: what passing this node actually unlocks, in place of
                  the template's fabricated "+15% Action Speed" chips. */}
              <p style={{ fontSize: 13 }}>
                {children.length > 0
                  ? `Unlocks: ${children.map((c) => c.title).join(', ')}`
                  : 'Counts toward mastery'}
              </p>
            </div>
          </div>

          <div
            className="panel"
            style={{ display: 'flex', alignItems: 'center', gap: 16 }}
          >
            <div>
              <p className="dim pixel-font" style={{ fontSize: 10, marginBottom: 4 }}>
                STATUS
              </p>
              <p className="pixel-font" style={{ fontSize: 16 }}>
                {STATUS_LABEL[skill.status]}
              </p>
            </div>
            <button
              className={skill.status === 'available' ? 'accent' : undefined}
              disabled={skill.status !== 'available'}
              onClick={() => onAudit(skill.id, skill.node_type, 'day')}
              style={{ flex: 1 }}
            >
              {skill.status === 'mastered'
                ? 'Mastered'
                : skill.status === 'locked'
                  ? 'Locked'
                  : 'Allocate Skill Point →'}
            </button>
          </div>
        </div>
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
