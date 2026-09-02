import { useEffect, useState } from 'react'
import { api } from '../api'
import type { AuditMode, NodeType, StudyPlan as StudyPlanData } from '../types'

function formatDate(iso: string): string {
  const d = new Date(iso)
  return Number.isNaN(d.getTime()) ? '' : d.toLocaleString()
}

export default function StudyPlan({
  onAudit,
}: {
  onAudit: (skillId: number, nodeType: NodeType, mode: AuditMode) => void
}) {
  const [plan, setPlan] = useState<StudyPlanData | null>(null)
  const [loading, setLoading] = useState(true)
  const [generating, setGenerating] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    api
      .getCurrentPlan()
      .then(setPlan)
      .catch((e) => setError(String(e)))
      .finally(() => setLoading(false))
  }, [])

  async function generate() {
    setGenerating(true)
    setError(null)
    try {
      setPlan(await api.generatePlan())
    } catch (e) {
      setError(String(e))
    } finally {
      setGenerating(false)
    }
  }

  if (loading) return <p className="dim">Loading plan…</p>

  return (
    <div>
      <h2 className="pixel-font" style={{ fontSize: 18 }}>
        Study Plan
      </h2>
      <p className="dim" style={{ marginBottom: 24 }}>
        What to do next, and why in this order. The skill tree says what a subject is made of;
        this says where to start.
      </p>

      <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 20, flexWrap: 'wrap' }}>
        <button className="accent" onClick={generate} disabled={generating}>
          {generating ? 'Planning…' : plan ? 'Re-plan' : 'Build a plan'}
        </button>
        {plan && (
          <span className="dim" style={{ fontSize: 11 }}>
            Built {formatDate(plan.created_at)} · difficulty {plan.suggested_tier} · readiness{' '}
            {plan.context_bucket}
          </span>
        )}
      </div>

      {error && <p style={{ color: 'var(--danger)', fontSize: 12 }}>{error}</p>}

      {!plan ? (
        <p className="dim">No plan yet. Build one from your current tree and recent record.</p>
      ) : plan.steps.length === 0 ? (
        <p className="dim">
          This plan has no live steps left — every node it pointed at is gone. Re-plan to get a
          current one.
        </p>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {plan.steps.map((step, i) => (
            <div key={step.skill_id} className="panel">
              <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, flexWrap: 'wrap' }}>
                <span className="pixel-font" style={{ fontSize: 12 }}>
                  {String(i + 1).padStart(2, '0')}
                </span>
                <span className="pixel-font" style={{ fontSize: 13, color: '#facc15' }}>
                  {step.skill_title}
                </span>
                <span className="tag tag--outline" style={{ fontSize: 10 }}>
                  {step.node_type}
                </span>
              </div>

              <p style={{ fontSize: 13, marginTop: 8, marginBottom: 6 }}>{step.rationale}</p>

              {step.focus_hint && (
                <p className="dim" style={{ fontSize: 12, margin: 0 }}>
                  Watch for: {step.focus_hint}
                </p>
              )}

              <button
                style={{ marginTop: 12 }}
                onClick={() => onAudit(step.skill_id, step.node_type, 'day' as AuditMode)}
              >
                Start audit
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
