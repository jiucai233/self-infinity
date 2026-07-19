import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi, beforeEach } from 'vitest'
import SkillTree, { computeSkillTreeLayout } from './SkillTree'
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

  describe('skill tree connector lines', () => {
    const treeWithEdges: SkillNode[] = [
      {
        id: 10,
        slug: 'root-mastered',
        title: '已掌握的根节点',
        description: '根节点',
        parent_id: null,
        status: 'mastered',
        node_type: 'concept',
        mastery_score: 88,
      },
      {
        id: 11,
        slug: 'available-child',
        title: '可审计的子节点',
        description: '已解锁的子节点',
        parent_id: 10,
        status: 'available',
        node_type: 'task',
        mastery_score: null,
      },
      {
        id: 12,
        slug: 'locked-child',
        title: '锁定的子节点',
        description: '还没解锁的子节点',
        parent_id: 10,
        status: 'locked',
        node_type: 'concept',
        mastery_score: null,
      },
    ]

    it('renders an SVG edge between a mastered parent and its available/locked children, styled differently', async () => {
      vi.mocked(api.listSkills).mockReset().mockResolvedValue(treeWithEdges)
      render(<SkillTree onAudit={vi.fn()} />)

      await waitFor(() => expect(screen.getByText('已掌握的根节点')).toBeInTheDocument())

      const activeEdge = document.querySelector('[data-testid="skill-edge-10-11"]')
      const lockedEdge = document.querySelector('[data-testid="skill-edge-10-12"]')

      expect(activeEdge).not.toBeNull()
      expect(lockedEdge).not.toBeNull()

      // jsdom does not perform real layout, so getBoundingClientRect() on the
      // measured cards returns all-zero rects — the component must still
      // render a (degenerate) path without throwing, and the visual
      // treatment of locked vs. available/mastered edges must differ via
      // class name, not measured pixel coordinates.
      expect(activeEdge?.getAttribute('class')).toContain('skill-edge--active')
      expect(activeEdge?.getAttribute('class')).not.toContain('skill-edge--locked')
      expect(lockedEdge?.getAttribute('class')).toContain('skill-edge--locked')
      expect(lockedEdge?.getAttribute('class')).not.toContain('skill-edge--active')
    })
  })

  describe('computeSkillTreeLayout (subtree-aware x positions)', () => {
    // Fixture mirrors the real bug report: two independent forests coexist
    // — a "Big-O 记号" tree and a "分布式系统概览" tree whose three children
    // each have exactly one grandchild. The regression was that grandchild
    // x-positions were assigned by flat-row slot index (ignoring which
    // parent they actually belong to), so a grandchild could render nowhere
    // near its real parent's column.
    function node(id: number, parent_id: number | null, title: string): SkillNode {
      return {
        id,
        slug: `n${id}`,
        title,
        description: '',
        parent_id,
        status: 'available',
        node_type: 'concept',
        mastery_score: null,
      }
    }

    const bigO = [
      node(1, null, 'Big-O 记号'),
      node(2, 1, '递归'),
      node(4, 1, '图的 BFS'),
      node(3, 2, '递归的子问题'),
    ]

    const distributedSystems = [
      node(12, null, '分布式系统概览'),
      node(13, 12, '数据复制与一致性'),
      node(14, 12, '分区与分片'),
      node(15, 12, '共识协议'),
      node(16, 13, '分布式存储实践'),
      node(17, 14, '分片实践'),
      node(18, 15, '共识实践'),
    ]

    const skills = [...bigO, ...distributedSystems]

    it('places a grandchild directly under its real parent, not a sibling-tree cousin', () => {
      const { positions } = computeSkillTreeLayout(skills)

      const x13 = positions.get(13)!.x
      const x14 = positions.get(14)!.x
      const x15 = positions.get(15)!.x
      const x16 = positions.get(16)!.x
      const x17 = positions.get(17)!.x
      const x18 = positions.get(18)!.x

      // Each grandchild is an only child, so a correct bottom-up centering
      // pass puts it at exactly the same column as its real parent.
      expect(x16).toBe(x13)
      expect(x17).toBe(x14)
      expect(x18).toBe(x15)

      // Sibling order under the shared root is preserved left-to-right.
      expect(x13).toBeLessThan(x14)
      expect(x14).toBeLessThan(x15)

      // 16's real parent (13) sits nowhere near its cousins' subtrees.
      expect(x16).not.toBe(x14)
      expect(x16).not.toBe(x15)
    })

    it('keeps separate root trees (forests) in non-overlapping column ranges', () => {
      const { positions } = computeSkillTreeLayout(skills)

      const bigOXs = bigO.map((s) => positions.get(s.id)!.x)
      const distributedXs = distributedSystems.map((s) => positions.get(s.id)!.x)

      expect(Math.max(...bigOXs)).toBeLessThan(Math.min(...distributedXs))
    })

    it('centers a parent with multiple children over the mean of their columns', () => {
      const { positions } = computeSkillTreeLayout(skills)

      const x1 = positions.get(1)!.x
      const x2 = positions.get(2)!.x
      const x4 = positions.get(4)!.x

      expect(x1).toBeCloseTo((x2 + x4) / 2)
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
