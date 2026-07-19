import { useEffect, useState } from 'react'
import { api } from '../api'
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

const STATUS_TAG_CLASS: Record<SkillNode['status'], string> = {
  locked: 'tag tag--outline',
  available: 'tag tag--outline',
  mastered: 'tag tag--filled',
}

// Mirrors backend/app/routers/skills.py's _resolve_max_turns day-mode
// defaults, display-only — same estimate AuditRoom.tsx uses for its
// progress bar. Kept local rather than shared since it's decorative
// (a display estimate, not the source of truth the backend enforces).
const DAY_MAX_TURNS: Record<SkillNode['node_type'], number> = {
  concept: 4,
  task: 2,
}

// decorative: no real "advisor" system exists — a static flavor line per
// node type, standing in for the template's NEURAL ADVISOR quote box.
const AUDITOR_NOTE: Record<SkillNode['node_type'], string> = {
  concept: 'Explain it like the Auditor has never heard the term before — that’s the whole test.',
  task: 'Show the Auditor you actually did it. That’s the only bar that matters.',
}

const SEGMENT_COUNT = 24

function ProgressionSegments({ pct, mastered }: { pct: number; mastered: boolean }) {
  const filled = Math.round((pct / 100) * SEGMENT_COUNT)
  return (
    <div style={{ display: 'flex', gap: 2 }}>
      {Array.from({ length: SEGMENT_COUNT }).map((_, i) => (
        <div
          key={i}
          className={i < filled ? 'pixel-bar-segment active' : 'pixel-bar-segment'}
          style={i < filled ? { background: mastered ? '#facc15' : 'var(--text)' } : undefined}
        />
      ))}
    </div>
  )
}

// Small connected-chip chain for the bottom prerequisite row — real
// ancestor/descendant data (walked from parent_id), not the template's
// fictional "CALM BREATH -- INITIAL FOCUS -- FLOW TRANCE" ability names.
function ChainNode({ title, current }: { title: string; current?: boolean }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6 }}>
      <div
        className={current ? 'pixel-border-active' : 'pixel-border'}
        style={{ width: 40, height: 40 }}
      />
      <span
        className="dim"
        style={{
          fontSize: 10,
          maxWidth: 80,
          textAlign: 'center',
          color: current ? 'var(--text)' : undefined,
        }}
      >
        {title}
      </span>
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
  const [copied, setCopied] = useState(false)

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

  const byId = new Map(skills.map((s) => [s.id, s]))

  // real: walk parent_id up to the root for the breadcrumb and the
  // left half of the prerequisite chain, instead of a fixed 2-level
  // "Skills > NODE DETAIL" breadcrumb.
  const ancestors: SkillNode[] = []
  let cursor = skill.parent_id != null ? byId.get(skill.parent_id) : undefined
  while (cursor) {
    ancestors.unshift(cursor)
    cursor = cursor.parent_id != null ? byId.get(cursor.parent_id) : undefined
  }

  const children = skills.filter((s) => s.parent_id === skill.id)
  const masteredCount = skills.filter((s) => s.status === 'mastered').length
  const progressionPct = skill.status === 'mastered' ? (skill.mastery_score ?? 100) : 0
  const maxTurns = DAY_MAX_TURNS[skill.node_type]

  function copySummary() {
    const summary = `${skill!.title} — ${STATUS_LABEL[skill!.status]} on Self-Infinity`
    navigator.clipboard?.writeText(summary).then(() => {
      setCopied(true)
      setTimeout(() => setCopied(false), 1500)
    })
  }

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
        {ancestors.map((a) => (
          <span key={a.id}> &gt; {a.title}</span>
        ))}
        {' > '}
        <span style={{ color: 'var(--text)' }}>{skill.title}</span>
      </p>

      {/* Two-column layout per the higher-fidelity
          skill_tree_detail_pixel_mono_white_standardized ("Deep Focus
          Protocol") reference — ability card + progression + status/unlocks
          on the left, an advisor-note + audit-intensity sidebar on the
          right, prerequisite chain spanning the full width below. */}
      <div
        style={{
          display: 'grid',
          gridTemplateColumns: '2fr minmax(220px, 1fr)',
          gap: 16,
          marginBottom: 16,
          alignItems: 'start',
        }}
      >
        <div className="panel">
          <div
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'flex-start',
              marginBottom: 12,
            }}
          >
            <div style={{ display: 'flex', gap: 12 }}>
              <div className="pixel-border" style={{ width: 48, height: 48, flexShrink: 0 }} />
              <div>
                <h2 className="pixel-font" style={{ fontSize: 16, marginBottom: 8 }}>
                  {skill.title}
                </h2>
                <div style={{ display: 'flex', gap: 6 }}>
                  <span className={STATUS_TAG_CLASS[skill.status]}>
                    {STATUS_LABEL[skill.status]}
                  </span>
                  <span className="tag tag--outline">{NODE_TYPE_LABEL[skill.node_type]}</span>
                </div>
              </div>
            </div>
            {skill.status === 'mastered' && (
              <div style={{ textAlign: 'right' }}>
                <p className="dim pixel-font" style={{ fontSize: 9 }}>
                  MASTERY SCORE
                </p>
                <p className="pixel-font" style={{ fontSize: 18, color: '#facc15' }}>
                  {Math.round(progressionPct)}%
                </p>
              </div>
            )}
          </div>

          <p style={{ fontSize: 13, marginBottom: 16 }}>{skill.description}</p>

          <p className="dim pixel-font" style={{ fontSize: 10, marginBottom: 8 }}>
            PROGRESSION
          </p>
          <ProgressionSegments pct={progressionPct} mastered={skill.status === 'mastered'} />
          <p className="dim" style={{ fontSize: 12, marginTop: 6, marginBottom: 16 }}>
            {Math.round(progressionPct)}%
          </p>

          <div
            style={{
              display: 'grid',
              gridTemplateColumns: '1fr 1fr',
              gap: 16,
              marginBottom: 16,
            }}
          >
            <div className="pixel-border" style={{ padding: 12 }}>
              <p className="dim pixel-font" style={{ fontSize: 9, marginBottom: 8 }}>
                STATUS
              </p>
              {/* real: the node's actual status/type, not the template's
                  fabricated "+15% Action Speed" style buff lines. */}
              <p style={{ fontSize: 13 }}>{STATUS_LABEL[skill.status]}</p>
            </div>
            <div className="pixel-border" style={{ padding: 12 }}>
              <p className="dim pixel-font" style={{ fontSize: 9, marginBottom: 8 }}>
                UNLOCKS NEXT
              </p>
              {/* real: actual child nodes, derived from parent_id — not a
                  fabricated ability name. */}
              <p style={{ fontSize: 13 }}>
                {children.length > 0
                  ? children.map((c) => c.title).join(', ')
                  : 'No further nodes yet'}
              </p>
            </div>
          </div>

          <div style={{ display: 'flex', gap: 8 }}>
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
                  : 'Allocate Skill Point'}
            </button>
            <button type="button" onClick={copySummary} title="Copy a shareable summary">
              {copied ? 'Copied!' : 'Share'}
            </button>
          </div>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          <div className="panel">
            <p className="dim pixel-font" style={{ fontSize: 10, marginBottom: 10 }}>
              AUDITOR&apos;S NOTE
            </p>
            <p style={{ fontSize: 13, fontStyle: 'italic' }}>
              &ldquo;{AUDITOR_NOTE[skill.node_type]}&rdquo;
            </p>
          </div>

          <div className="panel">
            <p className="dim pixel-font" style={{ fontSize: 10, marginBottom: 12 }}>
              AUDIT INTENSITY
            </p>
            {/* real: mirrors the backend's day-mode max-turns resolution
                for this node type (see AuditRoom.tsx's own mirror of the
                same constants) — not a fabricated radial gauge. */}
            <div
              style={{
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: 12,
              }}
            >
              <div
                style={{ position: 'relative', width: 56, height: 56, flexShrink: 0 }}
              >
                <div className="force-field force-field--mid" style={{ inset: 0 }} />
              </div>
              <div>
                <p className="pixel-font" style={{ fontSize: 14 }}>
                  {maxTurns} rounds
                </p>
                <p className="dim" style={{ fontSize: 11 }}>
                  Day (Standard) mode
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* real prerequisite chain: ancestors -> this node (highlighted) ->
          children, walked from parent_id, per the template's
          PREREQUISITE MAPPING row. */}
      <div className="panel" style={{ marginBottom: 16 }}>
        <p className="dim pixel-font" style={{ fontSize: 10, marginBottom: 16 }}>
          PREREQUISITE MAPPING
        </p>
        <div style={{ display: 'flex', alignItems: 'flex-start', gap: 16, flexWrap: 'wrap' }}>
          {ancestors.map((a) => (
            <ChainNode key={a.id} title={a.title} />
          ))}
          <ChainNode title={skill.title} current />
          {children.map((c) => (
            <ChainNode key={c.id} title={c.title} />
          ))}
        </div>
      </div>

      <div className="avatar-stat-row">
        <div className="panel stat-card">
          <span className="dim pixel-font stat-card-label">UNLOCKED NODES</span>
          <span className="pixel-font stat-card-value">
            {masteredCount} / {skills.length}
          </span>
        </div>
      </div>
    </div>
  )
}
