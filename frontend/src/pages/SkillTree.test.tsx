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
    title: 'Locked Concept',
    description: 'Not unlocked yet',
    parent_id: null,
    status: 'locked',
    node_type: 'concept',
    mastery_score: null,
  },
  {
    id: 2,
    slug: 'available-task',
    title: 'Available Task',
    description: 'Ready to audit',
    parent_id: null,
    status: 'available',
    node_type: 'task',
    mastery_score: null,
  },
  {
    id: 3,
    slug: 'mastered-concept',
    title: 'Mastered Concept',
    description: 'Already passed audit',
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

    await waitFor(() => expect(screen.getByText('Locked Concept')).toBeInTheDocument())

    expect(screen.getAllByText('Concept · Explain the why')).toHaveLength(2)
    expect(screen.getByText('Task · Just get it done')).toBeInTheDocument()
  })

  it('calls onAudit with skillId and node_type when clicking an available node', async () => {
    const onAudit = vi.fn()
    const user = userEvent.setup()
    render(<SkillTree onAudit={onAudit} />)

    await waitFor(() => expect(screen.getByText('Available Task')).toBeInTheDocument())

    const card = screen.getByText('Available Task').closest('.panel') as HTMLElement
    const button = within(card).getByRole('button', { name: 'Start Audit' })
    await user.click(button)

    expect(onAudit).toHaveBeenCalledWith(2, 'task', 'day')
  })

  it('disables the audit button for a locked node', async () => {
    const onAudit = vi.fn()
    render(<SkillTree onAudit={onAudit} />)

    await waitFor(() => expect(screen.getByText('Locked Concept')).toBeInTheDocument())

    const card = screen.getByText('Locked Concept').closest('.panel') as HTMLElement
    const button = within(card).getByRole('button', { name: 'Start Audit' })
    expect(button).toBeDisabled()
  })

  it('defaults to day mode and calls onAudit with "day" when starting an audit', async () => {
    const onAudit = vi.fn()
    const user = userEvent.setup()
    render(<SkillTree onAudit={onAudit} />)

    await waitFor(() => expect(screen.getByText('Available Task')).toBeInTheDocument())

    const card = screen.getByText('Available Task').closest('.panel') as HTMLElement
    await user.click(within(card).getByRole('button', { name: 'Start Audit' }))

    expect(onAudit).toHaveBeenCalledWith(2, 'task', 'day')
  })

  it('switching to night mode calls onAudit with "night"', async () => {
    const onAudit = vi.fn()
    const user = userEvent.setup()
    render(<SkillTree onAudit={onAudit} />)

    await waitFor(() => expect(screen.getByText('Available Task')).toBeInTheDocument())

    await user.click(screen.getByRole('button', { name: 'Night (Deep)' }))

    const card = screen.getByText('Available Task').closest('.panel') as HTMLElement
    await user.click(within(card).getByRole('button', { name: 'Start Audit' }))

    expect(onAudit).toHaveBeenCalledWith(2, 'task', 'night')
  })

  describe('clarify-first generate flow', () => {
    it('when clarify says needs_clarification: false, calls generateTree directly with no intermediate step', async () => {
      vi.mocked(api.clarifyTopic).mockResolvedValue({ needs_clarification: false, questions: [] })
      vi.mocked(api.generateTree).mockResolvedValue([])
      const user = userEvent.setup()
      render(<SkillTree onAudit={vi.fn()} />)

      await waitFor(() => expect(screen.getByText('Available Task')).toBeInTheDocument())

      await user.type(screen.getByPlaceholderText(/B-trees/), 'Reinforcement learning')
      await user.click(screen.getByRole('button', { name: 'New Mission' }))

      await waitFor(() =>
        expect(api.generateTree).toHaveBeenCalledWith('Reinforcement learning'),
      )
      expect(screen.queryByText('Skip, generate anyway')).not.toBeInTheDocument()
    })

    it('when clarify says needs_clarification: true, renders question inputs and does not call generateTree yet', async () => {
      vi.mocked(api.clarifyTopic).mockResolvedValue({
        needs_clarification: true,
        questions: ['Which direction do you want to focus on?', 'What is the goal?'],
      })
      const user = userEvent.setup()
      render(<SkillTree onAudit={vi.fn()} />)

      await waitFor(() => expect(screen.getByText('Available Task')).toBeInTheDocument())

      await user.type(screen.getByPlaceholderText(/B-trees/), 'Cooking')
      await user.click(screen.getByRole('button', { name: 'New Mission' }))

      await waitFor(() =>
        expect(screen.getByText('Which direction do you want to focus on?')).toBeInTheDocument(),
      )
      expect(screen.getByText('What is the goal?')).toBeInTheDocument()
      expect(api.generateTree).not.toHaveBeenCalled()
    })

    it('answering the clarify questions and submitting calls generateTree with a combined string', async () => {
      vi.mocked(api.clarifyTopic).mockResolvedValue({
        needs_clarification: true,
        questions: ['Which direction do you want to focus on?'],
      })
      vi.mocked(api.generateTree).mockResolvedValue([])
      const user = userEvent.setup()
      render(<SkillTree onAudit={vi.fn()} />)

      await waitFor(() => expect(screen.getByText('Available Task')).toBeInTheDocument())

      await user.type(screen.getByPlaceholderText(/B-trees/), 'Cooking')
      await user.click(screen.getByRole('button', { name: 'New Mission' }))

      await waitFor(() =>
        expect(screen.getByText('Which direction do you want to focus on?')).toBeInTheDocument(),
      )
      await user.type(
        screen.getByLabelText('Which direction do you want to focus on?'),
        'Home cooking',
      )
      await user.click(screen.getByRole('button', { name: 'Generate' }))

      await waitFor(() => expect(api.generateTree).toHaveBeenCalled())
      const combined = vi.mocked(api.generateTree).mock.calls[0][0]
      expect(combined).toContain('Cooking')
      expect(combined).toContain('Which direction do you want to focus on?')
      expect(combined).toContain('Home cooking')
    })

    it('clicking "Skip, generate anyway" calls generateTree with just the original topic', async () => {
      vi.mocked(api.clarifyTopic).mockResolvedValue({
        needs_clarification: true,
        questions: ['Which direction do you want to focus on?'],
      })
      vi.mocked(api.generateTree).mockResolvedValue([])
      const user = userEvent.setup()
      render(<SkillTree onAudit={vi.fn()} />)

      await waitFor(() => expect(screen.getByText('Available Task')).toBeInTheDocument())

      await user.type(screen.getByPlaceholderText(/B-trees/), 'Cooking')
      await user.click(screen.getByRole('button', { name: 'New Mission' }))

      await waitFor(() =>
        expect(screen.getByText('Which direction do you want to focus on?')).toBeInTheDocument(),
      )
      await user.click(screen.getByRole('button', { name: 'Skip, generate anyway' }))

      await waitFor(() => expect(api.generateTree).toHaveBeenCalledWith('Cooking'))
    })

    it('falls back to generating directly when the clarify endpoint itself fails', async () => {
      vi.mocked(api.clarifyTopic).mockRejectedValue(new Error('502 Bad Gateway'))
      vi.mocked(api.generateTree).mockResolvedValue([])
      const user = userEvent.setup()
      render(<SkillTree onAudit={vi.fn()} />)

      await waitFor(() => expect(screen.getByText('Available Task')).toBeInTheDocument())

      await user.type(screen.getByPlaceholderText(/B-trees/), 'Reinforcement learning')
      await user.click(screen.getByRole('button', { name: 'New Mission' }))

      await waitFor(() =>
        expect(api.generateTree).toHaveBeenCalledWith('Reinforcement learning'),
      )
    })
  })

  describe('skill tree connector lines', () => {
    const treeWithEdges: SkillNode[] = [
      {
        id: 10,
        slug: 'root-mastered',
        title: 'Mastered Root Node',
        description: 'Root node',
        parent_id: null,
        status: 'mastered',
        node_type: 'concept',
        mastery_score: 88,
      },
      {
        id: 11,
        slug: 'available-child',
        title: 'Available Child Node',
        description: 'An unlocked child node',
        parent_id: 10,
        status: 'available',
        node_type: 'task',
        mastery_score: null,
      },
      {
        id: 12,
        slug: 'locked-child',
        title: 'Locked Child Node',
        description: 'A still-locked child node',
        parent_id: 10,
        status: 'locked',
        node_type: 'concept',
        mastery_score: null,
      },
    ]

    it('renders an SVG edge between a mastered parent and its available/locked children, styled differently', async () => {
      vi.mocked(api.listSkills).mockReset().mockResolvedValue(treeWithEdges)
      render(<SkillTree onAudit={vi.fn()} />)

      await waitFor(() => expect(screen.getByText('Mastered Root Node')).toBeInTheDocument())

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
    // — a "Big-O notation" tree and a "distributed systems overview" tree
    // whose three children each have exactly one grandchild. The regression
    // was that grandchild x-positions were assigned by flat-row slot index
    // (ignoring which parent they actually belong to), so a grandchild could
    // render nowhere near its real parent's column.
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
      node(1, null, 'Big-O notation'),
      node(2, 1, 'Recursion'),
      node(4, 1, 'Graph BFS'),
      node(3, 2, 'Recursive subproblems'),
    ]

    const distributedSystems = [
      node(12, null, 'Distributed systems overview'),
      node(13, 12, 'Replication & consistency'),
      node(14, 12, 'Partitioning & sharding'),
      node(15, 12, 'Consensus protocols'),
      node(16, 13, 'Distributed storage practice'),
      node(17, 14, 'Sharding practice'),
      node(18, 15, 'Consensus practice'),
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
    it('renders on first visit and stays dismissed after clicking "Got it" and a remount', async () => {
      const user = userEvent.setup()
      const { unmount } = render(<SkillTree onAudit={vi.fn()} />)

      await waitFor(() => expect(screen.getByText('How to Play')).toBeInTheDocument())

      await user.click(screen.getByRole('button', { name: 'Got it' }))
      expect(screen.queryByText('How to Play')).not.toBeInTheDocument()

      unmount()

      render(<SkillTree onAudit={vi.fn()} />)
      await waitFor(() => expect(screen.getByText('Available Task')).toBeInTheDocument())
      expect(screen.queryByText('How to Play')).not.toBeInTheDocument()
    })
  })
})
