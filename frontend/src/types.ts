export type SkillStatus = 'locked' | 'available' | 'mastered'
export type AuditStatus = 'active' | 'passed' | 'failed'
export type NodeType = 'concept' | 'task'

export interface SkillNode {
  id: number
  slug: string
  title: string
  description: string
  parent_id: number | null
  status: SkillStatus
  node_type: NodeType
  mastery_score: number | null
}

export interface AuditTurn {
  role: 'user' | 'auditor'
  content: string
}

export interface AuditSession {
  id: number
  skill_id: number
  status: AuditStatus
  score: number | null
  gaps: string[]
  comment: string | null
  turns: AuditTurn[]
}

export interface StartAuditResponse {
  session: AuditSession
  opening_question: string
}

export interface TurnResultResponse {
  type: 'probe' | 'verdict'
  question?: string
  passed?: boolean
  score?: number
  gaps?: string[]
  comment?: string
  unlocked_skill_ids: number[]
}

export interface Principle {
  id: number
  title: string
  body: string
  source_session_id: number
}
