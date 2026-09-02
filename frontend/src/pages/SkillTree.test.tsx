import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi, beforeEach } from 'vitest'
import SkillTree from './SkillTree'
import { api } from '../api'
import type { GraphResponse, SkillNode } from '../types'

vi.mock('../api', () => ({
  api: {
    listSkills: vi.fn(),
    getGraph: vi.fn(),
    getRecommendation: vi.fn(),
    generateTree: vi.fn(),
    clarifyTopic: vi.fn(),
  },
}))

// force-graph renders to a real <canvas> 2D context, which jsdom doesn't
// implement — mounting the genuine KnowledgeGraph here would throw
// (node_modules/force-graph reads ctx.scale on a null context). Stub it out
// so SkillTree's own tests stay focused on the recommendation list; the
// graph itself is only exercised via real-browser verification.
vi.mock('./KnowledgeGraph', () => ({
  default: () => <div data-testid="knowledge-graph-stub" />,
}))

const emptyGraph: GraphResponse = { nodes: [], edges: [] }

// Recommendation list only shows real "available" nodes — locked nodes
// aren't actionable yet, mastered ones are done, so neither belongs in a
// "what should I do next" list. This fixture deliberately includes one of
// each status to assert that filtering.
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
    vi.mocked(api.getGraph).mockReset().mockResolvedValue(emptyGraph)
    vi.mocked(api.getRecommendation)
      .mockReset()
      .mockResolvedValue({ context_bucket: 'mid', suggested_tier: 'easy', skill_tiers: {} })
    vi.mocked(api.generateTree).mockReset()
    vi.mocked(api.clarifyTopic).mockReset()
  })

  it('only lists available nodes as recommendations, not locked or mastered ones', async () => {
    render(<SkillTree onAudit={vi.fn()} />)

    await waitFor(() => expect(screen.getByText('Available Task')).toBeInTheDocument())

    expect(screen.getByText('Task · Just get it done')).toBeInTheDocument()
    expect(screen.queryByText('Locked Concept')).not.toBeInTheDocument()
    expect(screen.queryByText('Mastered Concept')).not.toBeInTheDocument()
  })

  it('shows an empty state when nothing is available yet', async () => {
    vi.mocked(api.listSkills).mockReset().mockResolvedValue([skills[0], skills[2]])
    render(<SkillTree onAudit={vi.fn()} />)

    await waitFor(() =>
      expect(
        screen.getByText(/Nothing available right now/),
      ).toBeInTheDocument(),
    )
  })

  it('shows an empty state when no skills exist yet', async () => {
    vi.mocked(api.listSkills).mockReset().mockResolvedValue([])
    render(<SkillTree onAudit={vi.fn()} />)

    await waitFor(() =>
      expect(screen.getByText(/No skills yet/)).toBeInTheDocument(),
    )
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

  it('calls onOpenDetail when clicking "Details"', async () => {
    const onOpenDetail = vi.fn()
    const user = userEvent.setup()
    render(<SkillTree onAudit={vi.fn()} onOpenDetail={onOpenDetail} />)

    await waitFor(() => expect(screen.getByText('Available Task')).toBeInTheDocument())

    const card = screen.getByText('Available Task').closest('.panel') as HTMLElement
    await user.click(within(card).getByRole('button', { name: 'Details' }))

    expect(onOpenDetail).toHaveBeenCalledWith(2)
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

  describe('nearest neighbors', () => {
    const graphWithNeighbors: GraphResponse = {
      nodes: [
        { id: 'skill-2', kind: 'skill', title: 'Available Task', status: 'available', node_type: 'task' },
        { id: 'skill-3', kind: 'skill', title: 'Mastered Concept', status: 'mastered', node_type: 'concept' },
        { id: 'principle-1', kind: 'principle', title: 'Check the base case first', status: null, node_type: null },
      ],
      edges: [
        { source: 'skill-3', target: 'skill-2', kind: 'parent', reason: null },
        { source: 'principle-1', target: 'skill-2', kind: 'origin', reason: null },
      ],
    }

    it('shows the nearest graph neighbors for a recommended node and can open a skill neighbor', async () => {
      vi.mocked(api.getGraph).mockReset().mockResolvedValue(graphWithNeighbors)
      const onOpenDetail = vi.fn()
      const user = userEvent.setup()
      render(<SkillTree onAudit={vi.fn()} onOpenDetail={onOpenDetail} />)

      await waitFor(() => expect(screen.getByText('Available Task')).toBeInTheDocument())
      expect(screen.getByText('Nearest in graph:')).toBeInTheDocument()
      expect(screen.getByText('Mastered Concept')).toBeInTheDocument()
      expect(screen.getByText(/Check the base case/)).toBeInTheDocument()

      await user.click(screen.getByText('Mastered Concept'))
      expect(onOpenDetail).toHaveBeenCalledWith(3)
    })
  })

  describe('bandit recommendation', () => {
    // Two available nodes: "Available Task" has more real unlock leverage
    // (2 children vs 0), so it would normally rank first — but the bandit
    // suggests "hard" and only "Available Concept" is tagged "hard", so it
    // should be floated to the top instead, with a "Suggested" badge.
    const twoAvailable: SkillNode[] = [
      skills[1],
      {
        id: 4,
        slug: 'available-concept',
        title: 'Available Concept',
        description: 'Also ready to audit',
        parent_id: null,
        status: 'available',
        node_type: 'concept',
        mastery_score: null,
      },
      {
        id: 5,
        slug: 'child-of-task',
        title: 'Child Of Task',
        description: 'unlocked by Available Task',
        parent_id: 2,
        status: 'locked',
        node_type: 'task',
        mastery_score: null,
      },
      {
        id: 6,
        slug: 'another-child-of-task',
        title: 'Another Child Of Task',
        description: 'also unlocked by Available Task',
        parent_id: 2,
        status: 'locked',
        node_type: 'task',
        mastery_score: null,
      },
    ]

    it('floats the bandit-suggested tier to the top and badges it, without changing the underlying leverage order otherwise', async () => {
      vi.mocked(api.listSkills).mockReset().mockResolvedValue(twoAvailable)
      vi.mocked(api.getRecommendation).mockReset().mockResolvedValue({
        context_bucket: 'high',
        suggested_tier: 'hard',
        skill_tiers: { '2': 'easy', '4': 'hard' },
      })

      render(<SkillTree onAudit={vi.fn()} />)

      await waitFor(() => expect(screen.getByText('Available Concept')).toBeInTheDocument())

      const cards = screen.getAllByRole('heading', { level: 3 })
      const titles = cards.map((c) => c.textContent)
      expect(titles.indexOf('Available Concept')).toBeLessThan(titles.indexOf('Available Task'))

      const suggestedCard = screen.getByText('Available Concept').closest('.panel') as HTMLElement
      expect(within(suggestedCard).getByText('Suggested')).toBeInTheDocument()

      const otherCard = screen.getByText('Available Task').closest('.panel') as HTMLElement
      expect(within(otherCard).queryByText('Suggested')).not.toBeInTheDocument()
    })

    it('does not crash and shows no suggestion banner when the recommendation call fails', async () => {
      vi.mocked(api.getRecommendation).mockReset().mockRejectedValue(new Error('502'))
      render(<SkillTree onAudit={vi.fn()} />)

      await waitFor(() => expect(screen.getByText('Available Task')).toBeInTheDocument())
      expect(screen.queryByText('Suggested')).not.toBeInTheDocument()
      expect(screen.queryByText(/Based on your recent audits/)).not.toBeInTheDocument()
    })
  })

  describe('clarify-first generate flow', () => {
    it('when clarify says needs_clarification: false, calls generateTree directly with no intermediate step', async () => {
      vi.mocked(api.clarifyTopic).mockResolvedValue({ needs_clarification: false, questions: [] })
      vi.mocked(api.generateTree).mockResolvedValue({ nodes: [], prerequisites: [], source: null })
      const user = userEvent.setup()
      render(<SkillTree onAudit={vi.fn()} />)

      await waitFor(() => expect(screen.getByText('Available Task')).toBeInTheDocument())

      await user.type(screen.getByPlaceholderText(/B-trees/), 'Reinforcement learning')
      await user.click(screen.getByRole('button', { name: 'New Mission' }))

      await waitFor(() =>
        expect(api.generateTree).toHaveBeenCalledWith(
          'Reinforcement learning',
          // Course-shape knobs ride along with every generate call; defaults
          // match the backend's so an untouched form behaves as before.
          { node_count: 12, max_depth: 4, difficulty: 'standard', search_syllabus: true },
        ),
      )
      expect(screen.queryByText('Skip, generate anyway')).not.toBeInTheDocument()
    })

    it('passes the chosen course shape to the Planner', async () => {
      vi.mocked(api.clarifyTopic).mockResolvedValue({ needs_clarification: false, questions: [] })
      vi.mocked(api.generateTree).mockResolvedValue({ nodes: [], prerequisites: [], source: null })

      render(<SkillTree onAudit={vi.fn()} />)
      await waitFor(() => expect(screen.getByPlaceholderText(/B-trees/)).toBeInTheDocument())

      await userEvent.selectOptions(screen.getByLabelText(/Depth/), 'deep')
      await userEvent.type(screen.getByPlaceholderText(/B-trees/), 'Reinforcement learning')
      await userEvent.click(screen.getByRole('button', { name: 'New Mission' }))

      await waitFor(() =>
        expect(api.generateTree).toHaveBeenCalledWith(
          'Reinforcement learning',
          expect.objectContaining({ difficulty: 'deep' }),
        ),
      )
    })

    it('credits the real course a tree was modelled on', async () => {
      vi.mocked(api.clarifyTopic).mockResolvedValue({ needs_clarification: false, questions: [] })
      vi.mocked(api.generateTree).mockResolvedValue({
        nodes: [],
        prerequisites: [],
        source: { course: 'UC Berkeley CS285', url: 'https://real.invalid/cs285' },
      })

      render(<SkillTree onAudit={vi.fn()} />)
      await waitFor(() => expect(screen.getByPlaceholderText(/B-trees/)).toBeInTheDocument())
      await userEvent.type(screen.getByPlaceholderText(/B-trees/), 'Reinforcement learning')
      await userEvent.click(screen.getByRole('button', { name: 'New Mission' }))

      const link = await screen.findByRole('link', { name: 'UC Berkeley CS285' })
      expect(link).toHaveAttribute('href', 'https://real.invalid/cs285')
    })

    it('says nothing about provenance when no syllabus was found', async () => {
      vi.mocked(api.clarifyTopic).mockResolvedValue({ needs_clarification: false, questions: [] })
      vi.mocked(api.generateTree).mockResolvedValue({ nodes: [], prerequisites: [], source: null })

      render(<SkillTree onAudit={vi.fn()} />)
      await waitFor(() => expect(screen.getByPlaceholderText(/B-trees/)).toBeInTheDocument())
      await userEvent.type(screen.getByPlaceholderText(/B-trees/), 'Reinforcement learning')
      await userEvent.click(screen.getByRole('button', { name: 'New Mission' }))

      await waitFor(() => expect(api.generateTree).toHaveBeenCalled())
      // Better to show nothing than to hint vaguely that a source exists.
      expect(screen.queryByText(/Structure modelled on/)).not.toBeInTheDocument()
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
      vi.mocked(api.generateTree).mockResolvedValue({ nodes: [], prerequisites: [], source: null })
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
      vi.mocked(api.generateTree).mockResolvedValue({ nodes: [], prerequisites: [], source: null })
      const user = userEvent.setup()
      render(<SkillTree onAudit={vi.fn()} />)

      await waitFor(() => expect(screen.getByText('Available Task')).toBeInTheDocument())

      await user.type(screen.getByPlaceholderText(/B-trees/), 'Cooking')
      await user.click(screen.getByRole('button', { name: 'New Mission' }))

      await waitFor(() =>
        expect(screen.getByText('Which direction do you want to focus on?')).toBeInTheDocument(),
      )
      await user.click(screen.getByRole('button', { name: 'Skip, generate anyway' }))

      await waitFor(() =>
        expect(api.generateTree).toHaveBeenCalledWith(
          'Cooking',
          { node_count: 12, max_depth: 4, difficulty: 'standard', search_syllabus: true },
        ),
      )
    })

    it('falls back to generating directly when the clarify endpoint itself fails', async () => {
      vi.mocked(api.clarifyTopic).mockRejectedValue(new Error('502 Bad Gateway'))
      vi.mocked(api.generateTree).mockResolvedValue({ nodes: [], prerequisites: [], source: null })
      const user = userEvent.setup()
      render(<SkillTree onAudit={vi.fn()} />)

      await waitFor(() => expect(screen.getByText('Available Task')).toBeInTheDocument())

      await user.type(screen.getByPlaceholderText(/B-trees/), 'Reinforcement learning')
      await user.click(screen.getByRole('button', { name: 'New Mission' }))

      await waitFor(() =>
        expect(api.generateTree).toHaveBeenCalledWith(
          'Reinforcement learning',
          // Course-shape knobs ride along with every generate call; defaults
          // match the backend's so an untouched form behaves as before.
          { node_count: 12, max_depth: 4, difficulty: 'standard', search_syllabus: true },
        ),
      )
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
