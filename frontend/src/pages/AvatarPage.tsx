import { useState } from 'react'
import { AvatarPortrait, VitalsPanel, useVitalityFocus } from '../components/Avatar'
import { api } from '../api'
import type { CheckInRequest, VitalityState } from '../types'

const RATING_OPTIONS: { value: 1 | 2 | 3; label: string }[] = [
  { value: 1, label: '差' },
  { value: 2, label: '一般' },
  { value: 3, label: '好' },
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

export default function AvatarPage() {
  const [spending, setSpending] = useState<1 | 2 | 3>(2)
  const [activity, setActivity] = useState<1 | 2 | 3>(2)
  const [eating, setEating] = useState<1 | 2 | 3>(2)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [result, setResult] = useState<VitalityState | null>(null)
  const [refreshKey, setRefreshKey] = useState(0)

  const { vitality, focus, loaded } = useVitalityFocus(refreshKey)

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

  return (
    <div>
      {/* 2-column dashboard grid — portrait + VITALS STATUS panels side by
          side, per character_dashboard_pixel_mono_white/screen.png. */}
      <div className="avatar-dashboard-grid">
        <div className="panel">
          <h2 className="pixel-font" style={{ fontSize: 13, marginBottom: 12 }}>
            分身
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

      {/* Real stat readout row — only numbers this app actually has
          (Health/Sanity from vitality, Focus from the latest focus session
          if one exists). No fabricated STRENGTH/DEXTERITY/LUCK stats. */}
      <div className="avatar-stat-row">
        <StatCard label="HEALTH" value={vitality ? `${Math.round(vitality.health)}` : '—'} />
        <StatCard
          label="SANITY"
          value={
            vitality
              ? `${Math.round(vitality.sanity)}/${Math.round(vitality.sanity_cap)}`
              : '—'
          }
        />
        {focus && focus.focus_score != null && (
          <StatCard label="FOCUS" value={`${Math.round(focus.focus_score)}`} />
        )}
      </div>

      <div className="panel">
        <h2 className="pixel-font" style={{ fontSize: 13, marginBottom: 12 }}>
          每日签到
        </h2>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          <RatingField label="消费" name="spending" value={spending} onChange={setSpending} />
          <RatingField label="运动" name="activity" value={activity} onChange={setActivity} />
          <RatingField label="饮食" name="eating" value={eating} onChange={setEating} />
        </div>
        <button
          className="accent"
          style={{ marginTop: 16 }}
          onClick={submit}
          disabled={submitting}
        >
          {submitting ? '提交中…' : '提交签到'}
        </button>

        {error && (
          <p style={{ color: 'var(--danger)', marginTop: 12, fontSize: 13 }}>{error}</p>
        )}

        {result && !error && (
          <p className="dim" style={{ marginTop: 12, fontSize: 13 }}>
            签到成功 · Health {Math.round(result.health)} · Sanity {Math.round(result.sanity)}/
            {Math.round(result.sanity_cap)}
          </p>
        )}
      </div>
    </div>
  )
}
