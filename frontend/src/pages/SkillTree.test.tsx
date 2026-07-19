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
    clarifyTopic: vi.fn(),
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
    window.localStorage.clear()
    vi.mocked(api.listSkills).mockReset().mockResolvedValue(skills)
    vi.mocked(api.generateTree).mockReset()
    vi.mocked(api.clarifyTopic).mockReset()
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

  describe('clarify-first generate flow', () => {
    it('when clarify says needs_clarification: false, calls generateTree directly with no intermediate step', async () => {
      vi.mocked(api.clarifyTopic).mockResolvedValue({ needs_clarification: false, questions: [] })
      vi.mocked(api.generateTree).mockResolvedValue([])
      const user = userEvent.setup()
      render(<SkillTree onAudit={vi.fn()} />)

      await waitFor(() => expect(screen.getByText('可审计的任务')).toBeInTheDocument())

      await user.type(screen.getByPlaceholderText(/B 树/), '强化学习')
      await user.click(screen.getByRole('button', { name: '生成技能树' }))

      await waitFor(() => expect(api.generateTree).toHaveBeenCalledWith('强化学习'))
      expect(screen.queryByText('跳过，直接生成')).not.toBeInTheDocument()
    })

    it('when clarify says needs_clarification: true, renders question inputs and does not call generateTree yet', async () => {
      vi.mocked(api.clarifyTopic).mockResolvedValue({
        needs_clarification: true,
        questions: ['想学哪个方向？', '目标是什么？'],
      })
      const user = userEvent.setup()
      render(<SkillTree onAudit={vi.fn()} />)

      await waitFor(() => expect(screen.getByText('可审计的任务')).toBeInTheDocument())

      await user.type(screen.getByPlaceholderText(/B 树/), '做饭')
      await user.click(screen.getByRole('button', { name: '生成技能树' }))

      await waitFor(() => expect(screen.getByText('想学哪个方向？')).toBeInTheDocument())
      expect(screen.getByText('目标是什么？')).toBeInTheDocument()
      expect(api.generateTree).not.toHaveBeenCalled()
    })

    it('answering the clarify questions and submitting calls generateTree with a combined string', async () => {
      vi.mocked(api.clarifyTopic).mockResolvedValue({
        needs_clarification: true,
        questions: ['想学哪个方向？'],
      })
      vi.mocked(api.generateTree).mockResolvedValue([])
      const user = userEvent.setup()
      render(<SkillTree onAudit={vi.fn()} />)

      await waitFor(() => expect(screen.getByText('可审计的任务')).toBeInTheDocument())

      await user.type(screen.getByPlaceholderText(/B 树/), '做饭')
      await user.click(screen.getByRole('button', { name: '生成技能树' }))

      await waitFor(() => expect(screen.getByText('想学哪个方向？')).toBeInTheDocument())
      await user.type(screen.getByLabelText('想学哪个方向？'), '家常菜')
      await user.click(screen.getByRole('button', { name: '生成' }))

      await waitFor(() => expect(api.generateTree).toHaveBeenCalled())
      const combined = vi.mocked(api.generateTree).mock.calls[0][0]
      expect(combined).toContain('做饭')
      expect(combined).toContain('想学哪个方向？')
      expect(combined).toContain('家常菜')
    })

    it('clicking "跳过，直接生成" calls generateTree with just the original topic', async () => {
      vi.mocked(api.clarifyTopic).mockResolvedValue({
        needs_clarification: true,
        questions: ['想学哪个方向？'],
      })
      vi.mocked(api.generateTree).mockResolvedValue([])
      const user = userEvent.setup()
      render(<SkillTree onAudit={vi.fn()} />)

      await waitFor(() => expect(screen.getByText('可审计的任务')).toBeInTheDocument())

      await user.type(screen.getByPlaceholderText(/B 树/), '做饭')
      await user.click(screen.getByRole('button', { name: '生成技能树' }))

      await waitFor(() => expect(screen.getByText('想学哪个方向？')).toBeInTheDocument())
      await user.click(screen.getByRole('button', { name: '跳过，直接生成' }))

      await waitFor(() => expect(api.generateTree).toHaveBeenCalledWith('做饭'))
    })

    it('falls back to generating directly when the clarify endpoint itself fails', async () => {
      vi.mocked(api.clarifyTopic).mockRejectedValue(new Error('502 Bad Gateway'))
      vi.mocked(api.generateTree).mockResolvedValue([])
      const user = userEvent.setup()
      render(<SkillTree onAudit={vi.fn()} />)

      await waitFor(() => expect(screen.getByText('可审计的任务')).toBeInTheDocument())

      await user.type(screen.getByPlaceholderText(/B 树/), '强化学习')
      await user.click(screen.getByRole('button', { name: '生成技能树' }))

      await waitFor(() => expect(api.generateTree).toHaveBeenCalledWith('强化学习'))
    })
  })

  describe('onboarding callout', () => {
    it('renders on first visit and stays dismissed after clicking "知道了" and a remount', async () => {
      const user = userEvent.setup()
      const { unmount } = render(<SkillTree onAudit={vi.fn()} />)

      await waitFor(() => expect(screen.getByText('怎么玩？')).toBeInTheDocument())

      await user.click(screen.getByRole('button', { name: '知道了' }))
      expect(screen.queryByText('怎么玩？')).not.toBeInTheDocument()

      unmount()

      render(<SkillTree onAudit={vi.fn()} />)
      await waitFor(() => expect(screen.getByText('可审计的任务')).toBeInTheDocument())
      expect(screen.queryByText('怎么玩？')).not.toBeInTheDocument()
    })
  })
})
