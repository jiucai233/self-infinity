import type {
  AuditMode,
  CheckInRequest,
  ClarifyResponse,
  CourseOptions,
  FocusSession,
  GenerateTreeResponse,
  GraphResponse,
  NarratorBriefing,
  Principle,
  RecommendationResponse,
  RelinkResponse,
  SearchPlan,
  SkillNode,
  StartAuditResponse,
  StudyPlan,
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

  getRecommendation: () => request<RecommendationResponse>('/skills/recommendation'),

  generateTree: (topic: string, options?: Partial<CourseOptions>) =>
    request<GenerateTreeResponse>('/skills/generate', {
      method: 'POST',
      body: JSON.stringify({ topic, ...options }),
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

  getGraph: () => request<GraphResponse>('/graph'),

  relinkGraph: () => request<RelinkResponse>('/graph/relink', { method: 'POST' }),

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

  getBriefing: () => request<NarratorBriefing>('/narrator/briefing'),
  // The only narrator call that spends money — briefing is pure DB.
  narrate: () => request<NarratorBriefing>('/narrator/narrate', { method: 'POST' }),

  getCurrentPlan: () => request<StudyPlan | null>('/plan/current'),
  generatePlan: () => request<StudyPlan>('/plan/generate', { method: 'POST' }),

  // Retrieval is always tied to a concrete gap or a stored misconception —
  // the backend 400s on a bare request. See app/agents/searcher.py.
  createSearchPlan: (skillId: number, body: { gap?: string; misconception_id?: number }) =>
    request<SearchPlan>(`/skills/${skillId}/search-plan`, {
      method: 'POST',
      body: JSON.stringify(body),
    }),
}
