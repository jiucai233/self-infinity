import { useEffect, useState } from 'react'
import { AvatarPortrait, VitalsPanel, useVitalityFocus } from '../components/Avatar'
import { api } from '../api'
import type { CheckInRequest, Principle, VitalityState } from '../types'

const RATING_OPTIONS: { value: 1 | 2 | 3; label: string }[] = [
  { value: 1, label: 'Poor' },
  { value: 2, label: 'Okay' },
  { value: 3, label: 'Good' },
]

function RatingField({
  label,
  value,
  onChange,
  name,
}: {
  label: string
  value: 1 | 2 | 3
  onChange: (v: 1 | 2 | 3) => void
  name: string
}) {
  return (
    <div>
      <p className="dim" style={{ fontSize: 12, marginBottom: 4 }}>
        {label}
      </p>
      <div style={{ display: 'flex', gap: 8 }}>
        {RATING_OPTIONS.map((opt) => (
          <label
            key={opt.value}
            style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: 13 }}
          >
            <input
              type="radio"
              name={name}
              value={opt.value}
              checked={value === opt.value}
              onChange={() => onChange(opt.value)}
              style={{ width: 'auto' }}
            />
            {opt.label}
          </label>
        ))}
      </div>
    </div>
  )
}

function StatCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="panel stat-card">
      <span className="dim pixel-font stat-card-label">{label}</span>
      <span className="pixel-font stat-card-value">{value}</span>
    </div>
  )
}

export default function AvatarPage({ onInitiateMission }: { onInitiateMission?: () => void }) {
  const [spending, setSpending] = useState<1 | 2 | 3>(2)
  const [activity, setActivity] = useState<1 | 2 | 3>(2)
  const [eating, setEating] = useState<1 | 2 | 3>(2)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [result, setResult] = useState<VitalityState | null>(null)
  const [refreshKey, setRefreshKey] = useState(0)
  const [principles, setPrinciples] = useState<Principle[]>([])

  const { vitality, focus, loaded } = useVitalityFocus(refreshKey)

  useEffect(() => {
    // Real data for "Equipped Gear" / "Recent Records" below — reuses the
    // existing principles endpoint instead of inventing fake gear/log
    // entries. Best-effort: if it fails, both panels just fall back to
    // decorative flavor content.
    api
      .listPrinciples()
      .then(setPrinciples)
      .catch(() => {})
  }, [refreshKey])

  async function submit() {
    setSubmitting(true)
    setError(null)
    const body: CheckInRequest = {
      spending_rating: spending,
      activity_rating: activity,
      eating_rating: eating,
    }
    try {
      const updated = await api.submitCheckIn(body)
      setResult(updated)
      setRefreshKey((k) => k + 1)
    } catch (e) {
      setError(String(e))
    } finally {
      setSubmitting(false)
    }
  }

  // decorative: Intellect derives from real recent-principle count (a cheap
  // proxy for "how much reflection has this person banked"); Strength/
  // Dexterity/Luck have no real backing stat in this app and are static
  // flavor values, per the template's four-attribute row.
  const attributes = [
    { label: 'Strength', value: 12 },
    { label: 'Dexterity', value: 14 },
    { label: 'Intellect', value: 10 + principles.length },
    { label: 'Luck', value: 7 },
  ]

  const recentPrinciples = principles.slice(0, 2)

  return (
    <div style={{ position: 'relative', paddingBottom: 48 }}>
      {/* 2-column dashboard grid — portrait + VITALS STATUS panels side by
          side, per character_dashboard_pixel_mono_white/screen.png. */}
      <div className="avatar-dashboard-grid">
        <div className="panel">
          <h2 className="pixel-font" style={{ fontSize: 13, marginBottom: 12 }}>
            Character
          </h2>
          <AvatarPortrait focus={focus} loaded={loaded} />
        </div>

        <div className="panel">
          <h2 className="pixel-font" style={{ fontSize: 13, marginBottom: 12 }}>
            VITALS STATUS
          </h2>
          <VitalsPanel vitality={vitality} />
        </div>
      </div>

      {/* Single stat-card row: real Focus reading (Health/Sanity already
          shown above in VITALS STATUS, no need to repeat them here) plus the
          decorative Strength/Dexterity/Intellect/Luck attributes from the
          template's attribute grid. Intellect derives from real principle
          count; Strength/Dexterity/Luck are static flavor values. */}
      <div className="avatar-stat-row">
        {focus && focus.focus_score != null && (
          <StatCard label="FOCUS" value={`${Math.round(focus.focus_score)}`} />
        )}
        {attributes.map((a) => (
          <StatCard key={a.label} label={a.label.toUpperCase()} value={`${a.value}`} />
        ))}
      </div>

      <div className="avatar-dashboard-grid" style={{ marginBottom: 16 }}>
        <div className="panel">
          <h2 className="pixel-font" style={{ fontSize: 13, marginBottom: 12 }}>
            Equipped Gear
          </h2>
          {recentPrinciples.length > 0 ? (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              {recentPrinciples.map((p) => (
                <div key={p.id} style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span style={{ fontSize: 13 }}>{p.title}</span>
                  <span className="tag tag--outline" style={{ fontSize: 11 }}>
                    +Audit Passed
                  </span>
                </div>
              ))}
            </div>
          ) : (
            <p className="dim" style={{ fontSize: 13 }}>
              No gear yet — pass an audit to earn your first Archive entry.
            </p>
          )}
        </div>

        <div className="panel">
          <h2 className="pixel-font" style={{ fontSize: 13, marginBottom: 12 }}>
            Recent Records
          </h2>
          {recentPrinciples.length > 0 ? (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              {recentPrinciples.map((p) => (
                <div key={p.id}>
                  <p style={{ fontSize: 13 }}>{p.title}</p>
                  <p className="dim" style={{ fontSize: 11 }}>
                    {p.body.slice(0, 60)}
                    {p.body.length > 60 ? '…' : ''}
                  </p>
                </div>
              ))}
            </div>
          ) : (
            <p className="dim" style={{ fontSize: 13 }}>
              Nothing logged yet.
            </p>
          )}
        </div>
      </div>

      <div className="panel">
        <h2 className="pixel-font" style={{ fontSize: 13, marginBottom: 12 }}>
          Daily Check-in
        </h2>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          <RatingField
            label="Spending"
            name="spending"
            value={spending}
            onChange={setSpending}
          />
          <RatingField
            label="Activity"
            name="activity"
            value={activity}
            onChange={setActivity}
          />
          <RatingField label="Diet" name="eating" value={eating} onChange={setEating} />
        </div>
        <button
          className="accent"
          style={{ marginTop: 16 }}
          onClick={submit}
          disabled={submitting}
        >
          {submitting ? 'Submitting…' : 'Submit Check-in'}
        </button>

        {error && (
          <p style={{ color: 'var(--danger)', marginTop: 12, fontSize: 13 }}>{error}</p>
        )}

        {result && !error && (
          <p className="dim" style={{ marginTop: 12, fontSize: 13 }}>
            Check-in complete · Health {Math.round(result.health)} · Sanity{' '}
            {Math.round(result.sanity)}/{Math.round(result.sanity_cap)}
          </p>
        )}
      </div>

      {onInitiateMission && (
        <button
          className="accent"
          style={{ position: 'fixed', bottom: 16, right: 76 }}
          onClick={onInitiateMission}
        >
          Initiate Mission
        </button>
      )}
    </div>
  )
}
