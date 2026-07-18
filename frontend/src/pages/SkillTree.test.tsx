import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi, beforeEach } from 'vitest'
import SkillTree from './SkillTree'
import { api } from '../api'
import type { SkillNode } from '../types'

vi.mock('../api', () => ({
  api: {
    listSkills: vi.fn(),
    generateTree: vi.fn(),
  },
}))

const skills: SkillNode[] = [
  {
    id: 1,
    slug: 'locked-concept',
    title: '锁定的概念',
    description: '还没解锁',
    parent_id: null,
    status: 'locked',
    node_type: 'concept',
    mastery_score: null,
  },
  {
    id: 2,
    slug: 'available-task',
    title: '可审计的任务',
    description: '可以发起审计',
    parent_id: null,
    status: 'available',
    node_type: 'task',
    mastery_score: null,
  },
  {
    id: 3,
    slug: 'mastered-concept',
    title: '已掌握的概念',
    description: '已经通过审计',
    parent_id: null,
    status: 'mastered',
    node_type: 'concept',
    mastery_score: 92,
  },
]

describe('SkillTree', () => {
  beforeEach(() => {
    vi.mocked(api.listSkills).mockResolvedValue(skills)
  })

  it('renders concept/task badge labels for each node', async () => {
    render(<SkillTree onAudit={vi.fn()} />)

    await waitFor(() => expect(screen.getByText('锁定的概念')).toBeInTheDocument())

    expect(screen.getAllByText('概念 · 讲清楚为什么')).toHaveLength(2)
    expect(screen.getByText('任务 · 做到就行')).toBeInTheDocument()
  })

  it('calls onAudit with skillId and node_type when clicking an available node', async () => {
    const onAudit = vi.fn()
    const user = userEvent.setup()
    render(<SkillTree onAudit={onAudit} />)

    await waitFor(() => expect(screen.getByText('可审计的任务')).toBeInTheDocument())

    const card = screen.getByText('可审计的任务').closest('.panel') as HTMLElement
    const button = within(card).getByRole('button', { name: '发起审计' })
    await user.click(button)

    expect(onAudit).toHaveBeenCalledWith(2, 'task', 'day')
  })

  it('disables the audit button for a locked node', async () => {
    const onAudit = vi.fn()
    render(<SkillTree onAudit={onAudit} />)

    await waitFor(() => expect(screen.getByText('锁定的概念')).toBeInTheDocument())

    const card = screen.getByText('锁定的概念').closest('.panel') as HTMLElement
    const button = within(card).getByRole('button', { name: '发起审计' })
    expect(button).toBeDisabled()
  })

  it('defaults to day mode and calls onAudit with "day" when starting an audit', async () => {
    const onAudit = vi.fn()
    const user = userEvent.setup()
    render(<SkillTree onAudit={onAudit} />)

    await waitFor(() => expect(screen.getByText('可审计的任务')).toBeInTheDocument())

    const card = screen.getByText('可审计的任务').closest('.panel') as HTMLElement
    await user.click(within(card).getByRole('button', { name: '发起审计' }))

    expect(onAudit).toHaveBeenCalledWith(2, 'task', 'day')
  })

  it('switching to night mode calls onAudit with "night"', async () => {
    const onAudit = vi.fn()
    const user = userEvent.setup()
    render(<SkillTree onAudit={onAudit} />)

    await waitFor(() => expect(screen.getByText('可审计的任务')).toBeInTheDocument())

    await user.click(screen.getByRole('button', { name: '夜晚（深度）' }))

    const card = screen.getByText('可审计的任务').closest('.panel') as HTMLElement
    await user.click(within(card).getByRole('button', { name: '发起审计' }))

    expect(onAudit).toHaveBeenCalledWith(2, 'task', 'night')
  })
})
