export type SkillStatus = 'locked' | 'available' | 'mastered'
export type AuditStatus = 'active' | 'passed' | 'failed'
export type NodeType = 'concept' | 'task'
export type AuditMode = 'day' | 'night'

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
  reward_amount: number | null
  reward_multiplier: number | null
}

export interface Principle {
  id: number
  title: string
  body: string
  source_session_id: number
}

export interface VitalityState {
  id: number
  health: number
  sanity: number
  sanity_cap: number
  updated_at: string
}

export interface FocusSession {
  id: number
  started_at: string
  ended_at: string | null
  focus_score: number | null
  source: string
}

export interface CheckInRequest {
  spending_rating: 1 | 2 | 3
  activity_rating: 1 | 2 | 3
  eating_rating: 1 | 2 | 3
}

export interface ClarifyResponse {
  needs_clarification: boolean
  questions: string[]
}

export type GraphNodeKind = 'skill' | 'principle'
export type GraphEdgeKind = 'parent' | 'origin' | 'related'

export interface GraphNode {
  id: string
  kind: GraphNodeKind
  title: string
  status: SkillStatus | null
  node_type: NodeType | null
}

export interface GraphEdge {
  source: string
  target: string
  kind: GraphEdgeKind
}

export interface GraphResponse {
  nodes: GraphNode[]
  edges: GraphEdge[]
}
