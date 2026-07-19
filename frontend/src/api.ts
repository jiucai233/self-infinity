import type {
  AuditMode,
  CheckInRequest,
  ClarifyResponse,
  FocusSession,
  Principle,
  SkillNode,
  StartAuditResponse,
  TurnResultResponse,
  VitalityState,
} from './types'

async function request<T>(path: string, options?: RequestInit): Promise<T> {
  const res = await fetch(`/api${path}`, {
    headers: { 'Content-Type': 'application/json' },
    ...options,
  })
  if (!res.ok) {
    const body = await res.text()
    throw new Error(`${res.status} ${res.statusText}: ${body}`)
  }
  return res.json() as Promise<T>
}

export const api = {
  listSkills: () => request<SkillNode[]>('/skills'),

  generateTree: (topic: string) =>
    request<SkillNode[]>('/skills/generate', {
      method: 'POST',
      body: JSON.stringify({ topic }),
    }),

  clarifyTopic: (topic: string) =>
    request<ClarifyResponse>('/skills/clarify', {
      method: 'POST',
      body: JSON.stringify({ topic }),
    }),

  startAudit: (skillId: number, mode: AuditMode = 'day') =>
    request<StartAuditResponse>(`/skills/${skillId}/audits`, {
      method: 'POST',
      body: JSON.stringify({ mode }),
    }),

  submitTurn: (auditId: number, content: string) =>
    request<TurnResultResponse>(`/audits/${auditId}/turns`, {
      method: 'POST',
      body: JSON.stringify({ content }),
    }),

  submitReflection: (auditId: number, reflection: string) =>
    request<Principle>(`/audits/${auditId}/reflection`, {
      method: 'POST',
      body: JSON.stringify({ reflection }),
    }),

  listPrinciples: () => request<Principle[]>('/principles'),

  getVitality: () => request<VitalityState>('/vitality'),

  submitCheckIn: (body: CheckInRequest) =>
    request<VitalityState>('/checkins', {
      method: 'POST',
      body: JSON.stringify(body),
    }),

  // GET /api/focus/latest 404s if no audit has ever reached a verdict yet —
  // treat that as "no focus data" rather than an error.
  getLatestFocus: async (): Promise<FocusSession | null> => {
    try {
      return await request<FocusSession>('/focus/latest')
    } catch (e) {
      if (e instanceof Error && /^404\b/.test(e.message)) return null
      throw e
    }
  },
}
