import { useEffect, useState } from 'react'
import { api } from '../api'
import type { MisconceptionCluster, NarratorBriefing } from '../types'

function formatDate(iso: string): string {
  const d = new Date(iso)
  return Number.isNaN(d.getTime()) ? '' : d.toLocaleDateString()
}

function StatCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="panel stat-card">
      <span className="stat-card-label">{label}</span>
      <span className="stat-card-value">{value}</span>
    </div>
  )
}

/**
 * One recurring mental model. The cross-domain ones carry the whole point of
 * this page: the same wrong model showing up under unrelated skills means the
 * problem isn't the topic, it's how this person reasons — and that is a claim
 * only a system holding their full history can make.
 */
function BlindSpotCard({ cluster }: { cluster: MisconceptionCluster }) {
  const skills = cluster.skills.join(' · ')
  return (
    <div
      className="panel"
      style={cluster.cross_domain ? { borderLeft: '3px solid #facc15' } : undefined}
    >
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, flexWrap: 'wrap' }}>
        {cluster.cross_domain && (
          <span className="tag tag--filled" style={{ fontSize: 10 }}>
            CROSS-DOMAIN
          </span>
        )}
        <span className="dim" style={{ fontSize: 11 }}>
          {cluster.occurrences}× · last seen {formatDate(cluster.last_seen)}
        </span>
      </div>

      <p style={{ fontSize: 14, marginTop: 8, marginBottom: 6 }}>{cluster.label}</p>

      <p className="dim" style={{ fontSize: 12, margin: 0 }}>
        {cluster.cross_domain ? `Showed up under: ${skills}` : `Under: ${skills}`}
      </p>
    </div>
  )
}

export default function Narrator() {
  const [briefing, setBriefing] = useState<NarratorBriefing | null>(null)
  const [loading, setLoading] = useState(true)
  const [narrating, setNarrating] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    api
      .getBriefing()
      .then(setBriefing)
      .catch((e) => setError(String(e)))
      .finally(() => setLoading(false))
  }, [])

  async function regenerate() {
    setNarrating(true)
    setError(null)
    try {
      setBriefing(await api.narrate())
    } catch (e) {
      setError(String(e))
    } finally {
      setNarrating(false)
    }
  }

  if (loading) return <p className="dim">Reading your record…</p>
  if (error && !briefing) return <p style={{ color: 'var(--danger)' }}>{error}</p>
  if (!briefing) return null

  const passRate =
    briefing.pass_rate === null ? '—' : `${Math.round(briefing.pass_rate * 100)}%`

  return (
    <div>
      <h2 className="pixel-font" style={{ fontSize: 18 }}>
        Briefing
      </h2>
      <p className="dim" style={{ marginBottom: 24 }}>
        What the system has worked out about you so far.
      </p>

      <div className="panel" style={{ marginBottom: 24 }}>
        {briefing.narrative ? (
          <>
            <p style={{ fontSize: 14, margin: 0 }}>{briefing.narrative}</p>
            <div
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 12,
                marginTop: 14,
                flexWrap: 'wrap',
              }}
            >
              {/* The numbers on this page are always current; this paragraph
                  is a snapshot. Showing when it was written is what keeps a
                  stale reading from being taken as a description of now. */}
              <span className="dim" style={{ fontSize: 11 }}>
                Written {formatDate(briefing.narrative_generated_at ?? '')}
              </span>
              <button onClick={regenerate} disabled={narrating}>
                {narrating ? 'Writing…' : 'Rewrite'}
              </button>
            </div>
          </>
        ) : (
          <>
            <p className="dim" style={{ fontSize: 13, margin: 0 }}>
              No briefing written yet.
            </p>
            <button className="accent" onClick={regenerate} disabled={narrating} style={{ marginTop: 12 }}>
              {narrating ? 'Writing…' : 'Write briefing'}
            </button>
          </>
        )}
        {error && (
          <p style={{ color: 'var(--danger)', fontSize: 12, marginTop: 8, marginBottom: 0 }}>{error}</p>
        )}
      </div>

      <h3 className="pixel-font" style={{ fontSize: 13, marginBottom: 4 }}>
        Recurring Blind Spots
      </h3>
      <p className="dim" style={{ fontSize: 12, marginBottom: 12 }}>
        Wrong mental models diagnosed more than once. The cross-domain ones are the ones to worry
        about — they follow you between unrelated subjects.
      </p>

      {briefing.clusters.length === 0 ? (
        <p className="dim" style={{ marginBottom: 24 }}>
          Nothing recorded yet. Blind spots come from failed audits you've reflected on.
        </p>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12, marginBottom: 24 }}>
          {briefing.clusters.map((c) => (
            <BlindSpotCard key={`${c.label}-${c.first_seen}`} cluster={c} />
          ))}
        </div>
      )}

      <h3 className="pixel-font" style={{ fontSize: 13, marginBottom: 12 }}>
        Standing
      </h3>
      <div className="avatar-stat-row">
        <StatCard label="MASTERED" value={`${briefing.mastered_skills}/${briefing.total_skills}`} />
        <StatCard label="AUDITS" value={String(briefing.total_audits)} />
        <StatCard label="PASS RATE" value={passRate} />
        {briefing.health !== null && (
          <StatCard label="HEALTH" value={String(Math.round(briefing.health))} />
        )}
        {briefing.sanity !== null && (
          <StatCard label="SANITY" value={String(Math.round(briefing.sanity))} />
        )}
        {briefing.focus_score !== null && (
          <StatCard label="FOCUS" value={String(briefing.focus_score)} />
        )}
      </div>
    </div>
  )
}
