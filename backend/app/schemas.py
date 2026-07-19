from datetime import date, datetime

from pydantic import BaseModel, field_validator

from app.models import AuditStatus, NodeType, SkillStatus


def _not_blank(value: str) -> str:
    stripped = value.strip()
    if not stripped:
        raise ValueError("must not be empty or whitespace-only")
    return stripped


class GenerateTreeRequest(BaseModel):
    topic: str

    _validate_topic = field_validator("topic")(_not_blank)


class ClarifyRequest(BaseModel):
    topic: str

    _validate_topic = field_validator("topic")(_not_blank)


class ClarifyResponse(BaseModel):
    needs_clarification: bool
    questions: list[str]


def _validate_audit_mode(value: str) -> str:
    if value not in ("day", "night"):
        raise ValueError('mode must be "day" or "night"')
    return value


class StartAuditRequest(BaseModel):
    mode: str = "day"

    _validate_mode = field_validator("mode")(_validate_audit_mode)


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

    _validate_content = field_validator("content")(_not_blank)


class TurnResultResponse(BaseModel):
    type: str  # "probe" | "verdict"
    question: str | None = None
    passed: bool | None = None
    score: int | None = None
    gaps: list[str] | None = None
    comment: str | None = None
    unlocked_skill_ids: list[int] = []
    reward_amount: int | None = None
    reward_multiplier: float | None = None


class ReflectionRequest(BaseModel):
    reflection: str

    _validate_reflection = field_validator("reflection")(_not_blank)


class GraphNodeOut(BaseModel):
    id: str
    kind: str  # "skill" | "principle"
    title: str
    status: SkillStatus | None = None
    node_type: NodeType | None = None


class GraphEdgeOut(BaseModel):
    source: str
    target: str
    kind: str  # "parent" | "origin" | "related"


class GraphResponse(BaseModel):
    nodes: list[GraphNodeOut]
    edges: list[GraphEdgeOut]


class PrincipleOut(BaseModel):
    id: int
    title: str
    body: str
    source_session_id: int


class RewardEventOut(BaseModel):
    id: int
    session_id: int
    amount: int
    multiplier: float
    created_at: datetime


class DailyCheckInOut(BaseModel):
    id: int
    date: date
    spending_rating: int
    activity_rating: int
    eating_rating: int


class VitalityStateOut(BaseModel):
    id: int
    health: float
    sanity: float
    sanity_cap: float
    updated_at: datetime


class FocusSessionOut(BaseModel):
    id: int
    started_at: datetime
    ended_at: datetime | None
    focus_score: int | None
    source: str


def _validate_rating(value: int) -> int:
    if not 1 <= value <= 3:
        raise ValueError("must be between 1 and 3")
    return value


class CheckInRequest(BaseModel):
    spending_rating: int
    activity_rating: int
    eating_rating: int

    _validate_spending_rating = field_validator("spending_rating")(_validate_rating)
    _validate_activity_rating = field_validator("activity_rating")(_validate_rating)
    _validate_eating_rating = field_validator("eating_rating")(_validate_rating)
