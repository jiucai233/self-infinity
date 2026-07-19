import { useState } from 'react'
import Avatar from '../components/Avatar'
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

export default function AvatarPage() {
  const [spending, setSpending] = useState<1 | 2 | 3>(2)
  const [activity, setActivity] = useState<1 | 2 | 3>(2)
  const [eating, setEating] = useState<1 | 2 | 3>(2)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [result, setResult] = useState<VitalityState | null>(null)
  const [refreshKey, setRefreshKey] = useState(0)

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
    <div style={{ display: 'flex', gap: 24, flexWrap: 'wrap' }}>
      <Avatar key={refreshKey} />

      <div className="panel" style={{ flex: 1, minWidth: 260 }}>
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
