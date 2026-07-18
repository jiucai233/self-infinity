import { render, screen, waitFor } from '@testing-library/react'
import { describe, expect, it, vi, beforeEach } from 'vitest'
import Avatar from './Avatar'
import { api } from '../api'
import type { FocusSession, VitalityState } from '../types'

vi.mock('../api', () => ({
  api: {
    getVitality: vi.fn(),
    getLatestFocus: vi.fn(),
  },
}))

function vitality(overrides: Partial<VitalityState> = {}): VitalityState {
  return {
    id: 1,
    health: 80,
    sanity: 30,
    sanity_cap: 60,
    updated_at: '2026-07-19T00:00:00Z',
    ...overrides,
  }
}

function focus(overrides: Partial<FocusSession> = {}): FocusSession {
  return {
    id: 1,
    started_at: '2026-07-19T00:00:00Z',
    ended_at: '2026-07-19T00:10:00Z',
    focus_score: 80,
    source: 'audit',
    ...overrides,
  }
}

describe('Avatar', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('renders the sanity bar track scaled to sanity_cap and fill scaled to sanity/sanity_cap', async () => {
    vi.mocked(api.getVitality).mockResolvedValue(vitality({ sanity: 30, sanity_cap: 60 }))
    vi.mocked(api.getLatestFocus).mockResolvedValue(null)

    render(<Avatar />)

    const track = await screen.findByTestId('bar-track-Sanity')
    // sanity_cap 60 out of reference max 100 -> 60% track width
    expect(track).toHaveStyle({ width: '60%' })

    const fill = screen.getByTestId('bar-fill-Sanity')
    // sanity 30 / sanity_cap 60 -> 50% fill within the track
    expect(fill).toHaveStyle({ width: '50%' })
  })

  it('renders a shorter sanity track when sanity_cap is lower (low health)', async () => {
    vi.mocked(api.getVitality).mockResolvedValue(vitality({ sanity: 20, sanity_cap: 40 }))
    vi.mocked(api.getLatestFocus).mockResolvedValue(null)

    render(<Avatar />)

    const track = await screen.findByTestId('bar-track-Sanity')
    expect(track).toHaveStyle({ width: '40%' })
  })

  it('renders a dense/high force-field state for a high focus score', async () => {
    vi.mocked(api.getVitality).mockResolvedValue(vitality())
    vi.mocked(api.getLatestFocus).mockResolvedValue(focus({ focus_score: 90 }))

    render(<Avatar />)

    await waitFor(() =>
      expect(screen.getByTestId('force-field')).toHaveAttribute('data-band', 'high'),
    )
  })

  it('renders a broken/low force-field state for a low focus score', async () => {
    vi.mocked(api.getVitality).mockResolvedValue(vitality())
    vi.mocked(api.getLatestFocus).mockResolvedValue(focus({ focus_score: 10 }))

    render(<Avatar />)

    await waitFor(() =>
      expect(screen.getByTestId('force-field')).toHaveAttribute('data-band', 'low'),
    )
  })

  it('renders a neutral idle force-field state when no focus session exists yet, without crashing', async () => {
    vi.mocked(api.getVitality).mockResolvedValue(vitality())
    vi.mocked(api.getLatestFocus).mockResolvedValue(null)

    render(<Avatar />)

    await waitFor(() =>
      expect(screen.getByTestId('force-field')).toHaveAttribute('data-band', 'idle'),
    )
    expect(await screen.findByText('尚无专注度数据')).toBeInTheDocument()
  })
})
