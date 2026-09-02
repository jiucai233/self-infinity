import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import Narrator from './Narrator'
import { api } from '../api'
import type { MisconceptionCluster, NarratorBriefing } from '../types'

vi.mock('../api', () => ({
  api: {
    getBriefing: vi.fn(),
    narrate: vi.fn(),
  },
}))

function cluster(overrides: Partial<MisconceptionCluster> = {}): MisconceptionCluster {
  return {
    label: '以为相关性就是因果关系',
    occurrences: 2,
    skills: ['统计学', '投资'],
    cross_domain: true,
    first_seen: '2026-08-01T00:00:00Z',
    last_seen: '2026-09-01T00:00:00Z',
    principle_ids: [1, 2],
    ...overrides,
  }
}

function briefing(overrides: Partial<NarratorBriefing> = {}): NarratorBriefing {
  return {
    total_skills: 4,
    mastered_skills: 1,
    available_skills: 2,
    total_audits: 3,
    passed_audits: 1,
    failed_audits: 2,
    pass_rate: 1 / 3,
    clusters: [],
    health: 80,
    sanity: 60,
    focus_score: 72,
    narrative: null,
    narrative_generated_at: null,
    ...overrides,
  }
}

describe('Narrator', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(api.getBriefing).mockResolvedValue(briefing())
  })

  it('offers to write a briefing when none exists yet', async () => {
    render(<Narrator />)

    await waitFor(() => expect(screen.getByText('No briefing written yet.')).toBeInTheDocument())
    expect(screen.getByRole('button', { name: 'Write briefing' })).toBeInTheDocument()
  })

  it('does not generate a narrative just by opening the page', async () => {
    render(<Narrator />)

    await waitFor(() => expect(api.getBriefing).toHaveBeenCalled())
    // The landing screen must stay free — narrate() is the only paid call.
    expect(api.narrate).not.toHaveBeenCalled()
  })

  it('flags a cross-domain blind spot and names the subjects it spans', async () => {
    vi.mocked(api.getBriefing).mockResolvedValue(briefing({ clusters: [cluster()] }))

    render(<Narrator />)

    await waitFor(() => expect(screen.getByText('CROSS-DOMAIN')).toBeInTheDocument())
    expect(screen.getByText('以为相关性就是因果关系')).toBeInTheDocument()
    expect(screen.getByText(/统计学 · 投资/)).toBeInTheDocument()
  })

  it('does not flag a blind spot confined to one subject', async () => {
    vi.mocked(api.getBriefing).mockResolvedValue(
      briefing({ clusters: [cluster({ cross_domain: false, skills: ['统计学'] })] }),
    )

    render(<Narrator />)

    await waitFor(() => expect(screen.getByText('以为相关性就是因果关系')).toBeInTheDocument())
    expect(screen.queryByText('CROSS-DOMAIN')).not.toBeInTheDocument()
  })

  it('says so plainly when there is nothing recorded', async () => {
    render(<Narrator />)

    await waitFor(() =>
      expect(screen.getByText(/Blind spots come from failed audits/)).toBeInTheDocument(),
    )
  })

  it('shows a written briefing and offers to rewrite it', async () => {
    vi.mocked(api.getBriefing).mockResolvedValue(
      briefing({ narrative: '你反复栽在同一个心智模型上。', narrative_generated_at: '2026-09-01T00:00:00Z' }),
    )

    render(<Narrator />)

    await waitFor(() =>
      expect(screen.getByText('你反复栽在同一个心智模型上。')).toBeInTheDocument(),
    )
    expect(screen.getByRole('button', { name: 'Rewrite' })).toBeInTheDocument()
  })

  it('writes a briefing on demand', async () => {
    vi.mocked(api.narrate).mockResolvedValue(
      briefing({ narrative: '新写的一段。', narrative_generated_at: '2026-09-02T00:00:00Z' }),
    )

    render(<Narrator />)
    await waitFor(() => expect(screen.getByRole('button', { name: 'Write briefing' })).toBeInTheDocument())
    await userEvent.click(screen.getByRole('button', { name: 'Write briefing' }))

    await waitFor(() => expect(screen.getByText('新写的一段。')).toBeInTheDocument())
  })

  it('surfaces a failure to write without losing the profile already on screen', async () => {
    vi.mocked(api.narrate).mockRejectedValue(new Error('502 Bad Gateway'))

    render(<Narrator />)
    await waitFor(() => expect(screen.getByRole('button', { name: 'Write briefing' })).toBeInTheDocument())
    await userEvent.click(screen.getByRole('button', { name: 'Write briefing' }))

    await waitFor(() => expect(screen.getByText(/502/)).toBeInTheDocument())
    // The numbers are computed locally and shouldn't vanish because the
    // narrative call failed.
    expect(screen.getByText('PASS RATE')).toBeInTheDocument()
  })

  it('renders a pass rate placeholder before any verdict exists', async () => {
    vi.mocked(api.getBriefing).mockResolvedValue(briefing({ pass_rate: null }))

    render(<Narrator />)

    await waitFor(() => expect(screen.getByText('PASS RATE')).toBeInTheDocument())
    expect(screen.getByText('—')).toBeInTheDocument()
  })
})
