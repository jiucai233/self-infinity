import { useEffect, useState } from 'react'
import { api } from '../api'
import type { FocusSession, VitalityState } from '../types'

// Reference max used to scale the Sanity track — whitepaper §7: "the Sanity
// bar's actual cap visibly scales with Health". sanity_cap is 40-100, so the track's
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

// Segmented pixel-style bar (row of discrete filled/unfilled squares,
// per stitch_continuous_momentum_tracker/character_dashboard_pixel_mono_white
// "HEALTH SCORE"/"MENTAL SCORE" bars) instead of one continuous rounded fill.
// The track container itself is still scaled to trackWidthPct so a lower
// sanity_cap keeps rendering visibly *fewer available segments*, not just
// fewer filled ones among a fixed set.
function Bar({
  label,
  displayLabel,
  value,
  max,
  trackMax,
  color,
  compact = false,
}: {
  label: string
  // Text shown to the user (e.g. "Health Score" / "Mental Score", per the
  // template's exact bar labels). Kept separate from `label` because
  // `label` also drives the data-testid ("bar-track-Health"/"bar-track-
  // Sanity") that existing tests key off of — renaming the displayed text
  // shouldn't require renaming those test hooks.
  displayLabel?: string
  value: number
  max: number
  trackMax: number
  color: string
  compact?: boolean
}) {
  const trackWidthPct = Math.max(0, Math.min(100, (max / trackMax) * 100))
  const fillWidthPct = max > 0 ? Math.max(0, Math.min(100, (value / max) * 100)) : 0
  const segmentCount = compact ? 8 : 20
  const filledSegments = Math.round((fillWidthPct / 100) * segmentCount)
  const shownLabel = displayLabel ?? label

  const track = (
    <div
      data-testid={`bar-track-${label}`}
      title={compact ? `${shownLabel} ${Math.round(value)}/${Math.round(max)}` : undefined}
      style={{
        width: `${trackWidthPct}%`,
        height: compact ? 6 : 12,
        display: 'flex',
        gap: compact ? 1 : 2,
      }}
    >
      {Array.from({ length: segmentCount }).map((_, i) => (
        <div
          key={i}
          data-testid={`bar-segment-${label}`}
          className={i < filledSegments ? 'pixel-bar-segment active' : 'pixel-bar-segment'}
          style={i < filledSegments ? { background: color } : undefined}
        />
      ))}
    </div>
  )

  if (compact) return track

  return (
    <div style={{ fontSize: 11 }}>
      <div className="dim pixel-font" style={{ marginBottom: 4, fontSize: 9 }}>
        {shownLabel} {Math.round(value)}/{Math.round(max)}
      </div>
      {track}
    </div>
  )
}

// Shared data-fetching hook — extracted so AvatarPage's dashboard grid can
// fetch vitality/focus once and hand the same data down to the split
// portrait/vitals panels below, instead of each panel re-fetching
// independently. `refreshKey` lets a caller force a refetch (e.g. after a
// check-in submission) without needing to remount the whole tree.
export function useVitalityFocus(refreshKey: number = 0) {
  const [vitality, setVitality] = useState<VitalityState | null>(null)
  const [focus, setFocus] = useState<FocusSession | null>(null)
  const [loaded, setLoaded] = useState(false)

  useEffect(() => {
    let cancelled = false
    setLoaded(false)
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
  }, [refreshKey])

  return { vitality, focus, loaded }
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
      aria-label="Cyber avatar"
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

// Just the portrait half of the non-compact Avatar render (ForceField +
// PixelFigure + focus caption) — split out so AvatarPage.tsx can place it in
// its own grid cell, per character_dashboard_pixel_mono_white/screen.png's
// top-left character panel. Takes vitality/focus/loaded as props (from
// useVitalityFocus) instead of fetching its own copy.
export function AvatarPortrait({
  focus,
  loaded,
}: {
  focus: FocusSession | null
  loaded: boolean
}) {
  const band = focusBand(focus?.focus_score ?? null)
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8 }}>
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
            ? `Focus ${Math.round(focus.focus_score ?? 0)}`
            : 'No focus data yet'
          : 'Loading…'}
      </p>
    </div>
  )
}

// Just the bars half of the non-compact Avatar render — split out so
// AvatarPage.tsx can place it in its own "VITALS STATUS" grid cell, per
// character_dashboard_pixel_mono_white/screen.png's top-right vitals panel.
export function VitalsPanel({ vitality }: { vitality: VitalityState | null }) {
  if (!vitality) return null
  return (
    <div style={{ width: '100%', display: 'flex', flexDirection: 'column', gap: 12 }}>
      <Bar
        label="Health"
        displayLabel="Health Score"
        value={vitality.health}
        max={100}
        trackMax={100}
        color="var(--accent)"
      />
      <Bar
        label="Sanity"
        displayLabel="Mental Score"
        value={vitality.sanity}
        max={vitality.sanity_cap}
        trackMax={SANITY_REFERENCE_MAX}
        color="#facc15"
      />
    </div>
  )
}

export default function Avatar({ compact = false }: { compact?: boolean }) {
  const { vitality, focus, loaded } = useVitalityFocus()
  const band = focusBand(focus?.focus_score ?? null)

  if (compact) {
    // Lives inline in App's sidebar, above the nav row — styled as
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
          borderRadius: 0,
          background: 'var(--panel-translucent)',
          border: '1px solid var(--border)',
          boxShadow: 'none',
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
            ? `Focus ${Math.round(focus.focus_score ?? 0)}`
            : 'No focus data yet'
          : 'Loading…'}
      </p>
    </div>
  )
}
