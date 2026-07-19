import { act, render, screen, waitFor } from '@testing-library/react'
import { afterEach, describe, expect, it, vi, beforeEach } from 'vitest'
import AuditRoom from './AuditRoom'
import { api } from '../api'
import type { StartAuditResponse } from '../types'

vi.mock('../api', () => ({
  api: {
    startAudit: vi.fn(),
    submitTurn: vi.fn(),
    submitReflection: vi.fn(),
  },
}))

function startAuditResponse(skillId: number): StartAuditResponse {
  return {
    session: {
      id: 100,
      skill_id: skillId,
      status: 'active',
      score: null,
      gaps: [],
      comment: null,
      turns: [],
    },
    opening_question: 'Opening question',
  }
}

describe('AuditRoom', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(api.startAudit).mockImplementation((skillId) =>
      Promise.resolve(startAuditResponse(skillId)),
    )
  })

  it('shows task-specific copy when nodeType is "task"', async () => {
    render(<AuditRoom skillId={1} nodeType="task" onDone={vi.fn()} />)

    await waitFor(() =>
      expect(
        screen.getByPlaceholderText('Explain exactly what you plan to do…'),
      ).toBeInTheDocument(),
    )
    expect(screen.getByRole('button', { name: 'Submit Plan' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Submit Explanation' })).not.toBeInTheDocument()
  })

  it('shows concept-specific copy when nodeType is "concept"', async () => {
    render(<AuditRoom skillId={1} nodeType="concept" onDone={vi.fn()} />)

    await waitFor(() =>
      expect(
        screen.getByPlaceholderText("Explain it to someone who's never heard of this…"),
      ).toBeInTheDocument(),
    )
    expect(screen.getByRole('button', { name: 'Submit Explanation' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Submit Plan' })).not.toBeInTheDocument()
  })

  it('shows task-specific verdict copy on pass/fail', async () => {
    vi.mocked(api.submitTurn).mockResolvedValue({
      type: 'verdict',
      passed: false,
      score: 40,
      gaps: ['Missing edge cases'],
      comment: 'Almost there',
      unlocked_skill_ids: [],
      reward_amount: null,
      reward_multiplier: null,
    })

    const user = (await import('@testing-library/user-event')).default.setup()
    render(<AuditRoom skillId={1} nodeType="task" onDone={vi.fn()} />)

    const textarea = await screen.findByPlaceholderText('Explain exactly what you plan to do…')
    await user.type(textarea, "Here's my plan")
    await user.click(screen.getByRole('button', { name: 'Submit Plan' }))

    await waitFor(() => expect(screen.getByText(/✗ Not There Yet/)).toBeInTheDocument())
  })

  it('shows reward feedback when the verdict includes a reward', async () => {
    vi.mocked(api.submitTurn).mockResolvedValue({
      type: 'verdict',
      passed: true,
      score: 90,
      gaps: [],
      comment: 'Very clearly explained',
      unlocked_skill_ids: [],
      reward_amount: 50,
      reward_multiplier: 1.5,
    })

    const user = (await import('@testing-library/user-event')).default.setup()
    render(<AuditRoom skillId={1} nodeType="concept" onDone={vi.fn()} />)

    const textarea = await screen.findByPlaceholderText(
      "Explain it to someone who's never heard of this…",
    )
    await user.type(textarea, 'Here is my explanation')
    await user.click(screen.getByRole('button', { name: 'Submit Explanation' }))

    await waitFor(() => expect(screen.getByText(/\+50 reward/)).toBeInTheDocument())
    expect(screen.getByText(/×1\.5/)).toBeInTheDocument()
  })

  describe('voice input', () => {
    let lastInstance: FakeSpeechRecognition | null = null

    class FakeSpeechRecognition {
      lang = ''
      continuous = false
      interimResults = false
      onresult: ((event: unknown) => void) | null = null
      onerror: ((event: unknown) => void) | null = null
      onend: (() => void) | null = null
      start = vi.fn()
      stop = vi.fn()
      constructor() {
        lastInstance = this
      }
    }

    afterEach(() => {
      lastInstance = null
      delete window.SpeechRecognition
      delete window.webkitSpeechRecognition
    })

    it('shows the mic button when SpeechRecognition is available and populates input on a result', async () => {
      // @ts-expect-error assigning a minimal fake to the browser global for testing
      window.SpeechRecognition = FakeSpeechRecognition

      const user = (await import('@testing-library/user-event')).default.setup()
      render(<AuditRoom skillId={1} nodeType="concept" onDone={vi.fn()} />)

      const micButton = await screen.findByRole('button', { name: 'Voice Input' })
      expect(micButton).toBeEnabled()
      await user.click(micButton)

      const textarea = screen.getByPlaceholderText(
        "Explain it to someone who's never heard of this…",
      ) as HTMLTextAreaElement

      await waitFor(() =>
        expect(screen.getByRole('button', { name: /Recording/ })).toBeInTheDocument(),
      )

      expect(lastInstance).not.toBeNull()
      act(() => {
        lastInstance!.onresult?.({
          resultIndex: 0,
          results: [{ isFinal: true, 0: { transcript: 'this is the transcribed result' } }],
        })
      })

      expect(textarea.value).toBe('this is the transcribed result')
      // does not auto-submit; user must still click the submit button
      expect(api.submitTurn).not.toHaveBeenCalled()
    })

    it('hides/disables the mic button when SpeechRecognition is unsupported', async () => {
      render(<AuditRoom skillId={1} nodeType="concept" onDone={vi.fn()} />)

      await screen.findByPlaceholderText("Explain it to someone who's never heard of this…")

      const micButton = screen.getByRole('button', { name: 'Voice Input' })
      expect(micButton).toBeDisabled()
    })
  })
})
