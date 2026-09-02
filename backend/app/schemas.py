from datetime import date, datetime

from pydantic import BaseModel, Field, field_validator

from app.models import AuditStatus, NodeType, SkillStatus


def _not_blank(value: str) -> str:
    stripped = value.strip()
    if not stripped:
        raise ValueError("must not be empty or whitespace-only")
    return stripped


def _validate_difficulty(value: str) -> str:
    if value not in ("intro", "standard", "deep"):
        raise ValueError('difficulty must be "intro", "standard" or "deep"')
    return value


class GenerateTreeRequest(BaseModel):
    topic: str
    # 课程规模的超参数。上下界是防呆而非性能考虑：少于 4 个节点不成课程，
    # 多于 30 个则单次生成的质量明显下降、开始出现凑数的空节点。
    node_count: int = Field(default=12, ge=4, le=30)
    max_depth: int = Field(default=4, ge=2, le=6)
    difficulty: str = "standard"

    _validate_topic = field_validator("topic")(_not_blank)
    _validate_difficulty = field_validator("difficulty")(_validate_difficulty)


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


class RecommendationOut(BaseModel):
    context_bucket: str
    suggested_tier: str
    skill_tiers: dict[int, str]


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
    kind: str  # "parent" | "origin" | "related" | "contradicts"
    reason: str | None = None


class GraphResponse(BaseModel):
    nodes: list[GraphNodeOut]
    edges: list[GraphEdgeOut]


class ContradictionOut(BaseModel):
    principle_a_id: int
    principle_a_title: str
    principle_b_id: int
    principle_b_title: str
    reason: str


class RelinkResponse(BaseModel):
    principles_processed: int
    related_links_created: int
    contradictions: list[ContradictionOut]


class PrincipleOut(BaseModel):
    id: int
    title: str
    body: str
    misconception: str | None
    source_session_id: int
    recurring_of_id: int | None = None
    recurring_of_title: str | None = None


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


class MisconceptionClusterOut(BaseModel):
    label: str
    occurrences: int
    skills: list[str]
    cross_domain: bool
    first_seen: datetime
    last_seen: datetime
    principle_ids: list[int]


class NarratorBriefingOut(BaseModel):
    total_skills: int
    mastered_skills: int
    available_skills: int
    total_audits: int
    passed_audits: int
    failed_audits: int
    pass_rate: float | None
    clusters: list[MisconceptionClusterOut]
    health: float | None
    sanity: float | None
    focus_score: int | None
    # 叙述与画像分开返回：画像永远是新鲜的（纯 DB 现算），叙述可能是上一次生成的
    # 快照，甚至为 None（从没生成过）。前端要能区分这两者，否则会把陈旧的叙述当成
    # 对当前状态的描述。
    narrative: str | None
    narrative_generated_at: datetime | None


class PlanStepOut(BaseModel):
    skill_id: int
    skill_title: str
    node_type: NodeType
    rationale: str
    focus_hint: str


class StudyPlanOut(BaseModel):
    id: int
    steps: list[PlanStepOut]
    suggested_tier: str
    context_bucket: str
    created_at: datetime


class SearchPlanRequest(BaseModel):
    """检索入口强制要求上下文。

    只接受"针对某个缺口/某个错误心智模型去找材料"，不接受"给我找这个主题的资料"——
    后者会让系统退化成资料推荐器，而本系统的立论是验证而非供给（白皮书 §1）。
    """

    gap: str | None = None
    misconception_id: int | None = None


class SearchPlanItemOut(BaseModel):
    title: str
    url: str
    snippet: str
    reason: str


class SearchPlanOut(BaseModel):
    id: int
    skill_id: int
    gap: str
    queries: list[str]
    items: list[SearchPlanItemOut]
    created_at: datetime


class SkillPrerequisiteOut(BaseModel):
    skill_id: int
    prerequisite_id: int
    reason: str


class GenerateTreeResponse(BaseModel):
    nodes: list[SkillNodeOut]
    prerequisites: list[SkillPrerequisiteOut]
