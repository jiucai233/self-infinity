import { useEffect, useState } from 'react'
import { api } from '../api'
import type { FocusSession, VitalityState } from '../types'

// Reference max used to scale the Sanity track — whitepaper §7: "Sanity 条的
// 实际上限随 Health 变化可视化伸缩". sanity_cap is 40-100, so the track's
// rendered width is a fraction of this reference, and the fill is a fraction
// of the track (sanity / sanity_cap). A low-health user therefore sees a
// visibly shorter overall Sanity bar, not just a differently-filled one.
const SANITY_REFERENCE_MAX = 100

type FocusBand = 'idle' | 'low' | 'mid' | 'high'

function focusBand(score: number | null): FocusBand {
  if (score === null) return 'idle'
  if (score >= 70) return 'high'
  if (score >= 35) return 'mid'
  return 'low'
}

function Bar({
  label,
  value,
  max,
  trackMax,
  color,
  compact = false,
}: {
  label: string
  value: number
  max: number
  trackMax: number
  color: string
  compact?: boolean
}) {
  const trackWidthPct = Math.max(0, Math.min(100, (max / trackMax) * 100))
  const fillWidthPct = max > 0 ? Math.max(0, Math.min(100, (value / max) * 100)) : 0
  const track = (
    <div
      data-testid={`bar-track-${label}`}
      title={compact ? `${label} ${Math.round(value)}/${Math.round(max)}` : undefined}
      style={{
        width: `${trackWidthPct}%`,
        height: compact ? 4 : 8,
        border: '1px solid var(--border)',
        borderRadius: 999,
        background: 'var(--bg)',
        overflow: 'hidden',
      }}
    >
      <div
        data-testid={`bar-fill-${label}`}
        style={{
          width: `${fillWidthPct}%`,
          height: '100%',
          background: color,
          borderRadius: 999,
        }}
      />
    </div>
  )

  if (compact) return track

  return (
    <div style={{ fontSize: 11 }}>
      <div className="dim" style={{ marginBottom: 2 }}>
        {label} {Math.round(value)}/{Math.round(max)}
      </div>
      {track}
    </div>
  )
}

function ForceField({ band }: { band: FocusBand }) {
  return (
    <div
      data-testid="force-field"
      data-band={band}
      className={`force-field force-field--${band}`}
    />
  )
}

function PixelFigure({ size = 48 }: { size?: number }) {
  // A handful of hard-edged rectangles standing in for the "cyber avatar" —
  // deliberately a placeholder silhouette, not a rendered character.
  const height = (size / 12) * 16
  return (
    <svg
      width={size}
      height={height}
      viewBox="0 0 12 16"
      shapeRendering="crispEdges"
      style={{ position: 'relative', zIndex: 1 }}
      role="img"
      aria-label="赛博分身"
    >
      <rect x="4" y="0" width="4" height="4" fill="var(--accent)" />
      <rect x="3" y="4" width="6" height="6" fill="var(--text)" />
      <rect x="1" y="5" width="2" height="4" fill="var(--text)" />
      <rect x="9" y="5" width="2" height="4" fill="var(--text)" />
      <rect x="3" y="10" width="2" height="6" fill="var(--dim)" />
      <rect x="7" y="10" width="2" height="6" fill="var(--dim)" />
    </svg>
  )
}

export default function Avatar({ compact = false }: { compact?: boolean }) {
  const [vitality, setVitality] = useState<VitalityState | null>(null)
  const [focus, setFocus] = useState<FocusSession | null>(null)
  const [loaded, setLoaded] = useState(false)

  useEffect(() => {
    let cancelled = false
    Promise.all([api.getVitality(), api.getLatestFocus()])
      .then(([v, f]) => {
        if (cancelled) return
        setVitality(v)
        setFocus(f)
      })
      .finally(() => {
        if (!cancelled) setLoaded(true)
      })
    return () => {
      cancelled = true
    }
  }, [])

  const band = focusBand(focus?.focus_score ?? null)

  if (compact) {
    // Lives inline in App's nav row, next to 技能树/分身/原则卷轴 — styled as
    // one more glass pill at the same height/alignment as those buttons
    // (not a separate floating widget), with Health/Sanity as small inline
    // bars stacked next to a mini icon instead of stacked text labels
    // floating above it.
    return (
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 8,
          padding: '6px 10px',
          borderRadius: 'var(--radius-pill)',
          background: 'var(--panel-sheen), var(--panel-translucent)',
          backdropFilter: 'blur(var(--glass-blur)) saturate(180%)',
          WebkitBackdropFilter: 'blur(var(--glass-blur)) saturate(180%)',
          border: '1px solid var(--border)',
          boxShadow: 'var(--shadow-soft-sm), inset 0 1px 0 var(--highlight)',
        }}
      >
        <div
          style={{
            position: 'relative',
            width: 26,
            height: 32,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            flexShrink: 0,
          }}
        >
          <ForceField band={band} />
          <PixelFigure size={20} />
        </div>

        {vitality && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 3, width: 44 }}>
            <Bar
              compact
              label="Health"
              value={vitality.health}
              max={100}
              trackMax={100}
              color="var(--accent)"
            />
            <Bar
              compact
              label="Sanity"
              value={vitality.sanity}
              max={vitality.sanity_cap}
              trackMax={SANITY_REFERENCE_MAX}
              color="#facc15"
            />
          </div>
        )}
      </div>
    )
  }

  return (
    <div
      className="panel"
      style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        gap: 8,
        width: 220,
      }}
    >
      {vitality && (
        <div style={{ width: '100%', display: 'flex', flexDirection: 'column', gap: 4 }}>
          <Bar
            label="Health"
            value={vitality.health}
            max={100}
            trackMax={100}
            color="var(--accent)"
          />
          <Bar
            label="Sanity"
            value={vitality.sanity}
            max={vitality.sanity_cap}
            trackMax={SANITY_REFERENCE_MAX}
            color="#facc15"
          />
        </div>
      )}

      <div
        style={{
          position: 'relative',
          width: 80,
          height: 80,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        <ForceField band={band} />
        <PixelFigure />
      </div>

      <p className="dim" style={{ fontSize: 11, textAlign: 'center' }}>
        {loaded
          ? focus
            ? `专注度 ${Math.round(focus.focus_score ?? 0)}`
            : '尚无专注度数据'
          : '加载中…'}
      </p>
    </div>
  )
}
