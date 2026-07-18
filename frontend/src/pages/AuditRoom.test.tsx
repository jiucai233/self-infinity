import { render, screen, waitFor } from '@testing-library/react'
import { describe, expect, it, vi, beforeEach } from 'vitest'
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
    })

    const user = (await import('@testing-library/user-event')).default.setup()
    render(<AuditRoom skillId={1} nodeType="task" onDone={vi.fn()} />)

    const textarea = await screen.findByPlaceholderText('说清楚具体打算怎么做…')
    await user.type(textarea, '我打算这样做')
    await user.click(screen.getByRole('button', { name: '提交说明' }))

    await waitFor(() => expect(screen.getByText(/✗ 还没做到/)).toBeInTheDocument())
  })
})
