import type {
  Principle,
  SkillNode,
  StartAuditResponse,
  TurnResultResponse,
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

  startAudit: (skillId: number) =>
    request<StartAuditResponse>(`/skills/${skillId}/audits`, { method: 'POST' }),

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
}
