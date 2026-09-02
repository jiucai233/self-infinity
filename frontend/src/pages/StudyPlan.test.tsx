import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import StudyPlan from './StudyPlan'
import { api } from '../api'
import type { StudyPlan as StudyPlanData } from '../types'

vi.mock('../api', () => ({
  api: {
    getCurrentPlan: vi.fn(),
    generatePlan: vi.fn(),
  },
}))

function plan(overrides: Partial<StudyPlanData> = {}): StudyPlanData {
  return {
    id: 1,
    steps: [
      {
        skill_id: 7,
        skill_title: '递归',
        node_type: 'concept',
        rationale: '它能解锁后面三个节点，而且难度正好匹配当前档位。',
        focus_hint: '说清楚为什么需要 base case。',
      },
    ],
    suggested_tier: 'medium',
    context_bucket: 'mid',
    created_at: '2026-09-02T00:00:00Z',
    ...overrides,
  }
}

describe('StudyPlan', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(api.getCurrentPlan).mockResolvedValue(null)
  })

  it('offers to build a plan when none exists', async () => {
    render(<StudyPlan onAudit={vi.fn()} />)

    await waitFor(() => expect(screen.getByRole('button', { name: 'Build a plan' })).toBeInTheDocument())
    expect(api.generatePlan).not.toHaveBeenCalled()
  })

  it('shows each step with the reason it is in this position', async () => {
    vi.mocked(api.getCurrentPlan).mockResolvedValue(plan())

    render(<StudyPlan onAudit={vi.fn()} />)

    await waitFor(() => expect(screen.getByText('递归')).toBeInTheDocument())
    expect(screen.getByText(/它能解锁后面三个节点/)).toBeInTheDocument()
    expect(screen.getByText(/说清楚为什么需要 base case/)).toBeInTheDocument()
    expect(screen.getByText(/difficulty medium/)).toBeInTheDocument()
  })

  it('starts an audit straight from a step', async () => {
    vi.mocked(api.getCurrentPlan).mockResolvedValue(plan())
    const onAudit = vi.fn()

    render(<StudyPlan onAudit={onAudit} />)
    await waitFor(() => expect(screen.getByRole('button', { name: 'Start audit' })).toBeInTheDocument())
    await userEvent.click(screen.getByRole('button', { name: 'Start audit' }))

    expect(onAudit).toHaveBeenCalledWith(7, 'concept', 'day')
  })

  it('tells the user to re-plan when every node it pointed at is gone', async () => {
    vi.mocked(api.getCurrentPlan).mockResolvedValue(plan({ steps: [] }))

    render(<StudyPlan onAudit={vi.fn()} />)

    await waitFor(() => expect(screen.getByText(/no live steps left/)).toBeInTheDocument())
  })

  it('surfaces a planning failure', async () => {
    vi.mocked(api.generatePlan).mockRejectedValue(new Error('400 no available nodes'))

    render(<StudyPlan onAudit={vi.fn()} />)
    await waitFor(() => expect(screen.getByRole('button', { name: 'Build a plan' })).toBeInTheDocument())
    await userEvent.click(screen.getByRole('button', { name: 'Build a plan' }))

    await waitFor(() => expect(screen.getByText(/no available nodes/)).toBeInTheDocument())
  })
})
