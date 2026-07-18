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
    opening_question: '开场问题',
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
        screen.getByPlaceholderText('说清楚具体打算怎么做…'),
      ).toBeInTheDocument(),
    )
    expect(screen.getByRole('button', { name: '提交说明' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: '提交解释' })).not.toBeInTheDocument()
  })

  it('shows concept-specific copy when nodeType is "concept"', async () => {
    render(<AuditRoom skillId={1} nodeType="concept" onDone={vi.fn()} />)

    await waitFor(() =>
      expect(
        screen.getByPlaceholderText('讲给一个完全没听说过的人听…'),
      ).toBeInTheDocument(),
    )
    expect(screen.getByRole('button', { name: '提交解释' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: '提交说明' })).not.toBeInTheDocument()
  })

  it('shows task-specific verdict copy on pass/fail', async () => {
    vi.mocked(api.submitTurn).mockResolvedValue({
      type: 'verdict',
      passed: false,
      score: 40,
      gaps: ['缺少边界情况'],
      comment: '还差一点',
      unlocked_skill_ids: [],
      reward_amount: null,
      reward_multiplier: null,
    })

    const user = (await import('@testing-library/user-event')).default.setup()
    render(<AuditRoom skillId={1} nodeType="task" onDone={vi.fn()} />)

    const textarea = await screen.findByPlaceholderText('说清楚具体打算怎么做…')
    await user.type(textarea, '我打算这样做')
    await user.click(screen.getByRole('button', { name: '提交说明' }))

    await waitFor(() => expect(screen.getByText(/✗ 还没做到/)).toBeInTheDocument())
  })

  it('shows reward feedback when the verdict includes a reward', async () => {
    vi.mocked(api.submitTurn).mockResolvedValue({
      type: 'verdict',
      passed: true,
      score: 90,
      gaps: [],
      comment: '讲得很清楚',
      unlocked_skill_ids: [],
      reward_amount: 50,
      reward_multiplier: 1.5,
    })

    const user = (await import('@testing-library/user-event')).default.setup()
    render(<AuditRoom skillId={1} nodeType="concept" onDone={vi.fn()} />)

    const textarea = await screen.findByPlaceholderText('讲给一个完全没听说过的人听…')
    await user.type(textarea, '这是我的解释')
    await user.click(screen.getByRole('button', { name: '提交解释' }))

    await waitFor(() => expect(screen.getByText(/\+50 奖励/)).toBeInTheDocument())
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

      const micButton = await screen.findByRole('button', { name: '语音输入' })
      expect(micButton).toBeEnabled()
      await user.click(micButton)

      const textarea = screen.getByPlaceholderText(
        '讲给一个完全没听说过的人听…',
      ) as HTMLTextAreaElement

      await waitFor(() =>
        expect(screen.getByRole('button', { name: /录音中/ })).toBeInTheDocument(),
      )

      expect(lastInstance).not.toBeNull()
      act(() => {
        lastInstance!.onresult?.({
          resultIndex: 0,
          results: [{ isFinal: true, 0: { transcript: '这是语音转文字的结果' } }],
        })
      })

      expect(textarea.value).toBe('这是语音转文字的结果')
      // does not auto-submit; user must still click the submit button
      expect(api.submitTurn).not.toHaveBeenCalled()
    })

    it('hides/disables the mic button when SpeechRecognition is unsupported', async () => {
      render(<AuditRoom skillId={1} nodeType="concept" onDone={vi.fn()} />)

      await screen.findByPlaceholderText('讲给一个完全没听说过的人听…')

      const micButton = screen.getByRole('button', { name: '语音输入' })
      expect(micButton).toBeDisabled()
    })
  })
})
