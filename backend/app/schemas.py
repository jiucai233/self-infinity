from pydantic import BaseModel

from app.models import AuditStatus, NodeType, SkillStatus


class GenerateTreeRequest(BaseModel):
    topic: str


class SkillNodeOut(BaseModel):
    id: int
    slug: str
    title: str
    description: str
    parent_id: int | None
    status: SkillStatus
    node_type: NodeType
    mastery_score: int | None


class AuditTurnOut(BaseModel):
    role: str
    content: str


class AuditSessionOut(BaseModel):
    id: int
    skill_id: int
    status: AuditStatus
    score: int | None
    gaps: list[str]
    comment: str | None
    turns: list[AuditTurnOut]


class StartAuditResponse(BaseModel):
    session: AuditSessionOut
    opening_question: str


class SubmitTurnRequest(BaseModel):
    content: str


class TurnResultResponse(BaseModel):
    type: str  # "probe" | "verdict"
    question: str | None = None
    passed: bool | None = None
    score: int | None = None
    gaps: list[str] | None = None
    comment: str | None = None
    unlocked_skill_ids: list[int] = []


class ReflectionRequest(BaseModel):
    reflection: str


class PrincipleOut(BaseModel):
    id: int
    title: str
    body: str
    source_session_id: int
