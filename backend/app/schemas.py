"""请求/响应的 JSON 形状，严格对应 docs/api-contract.md 第 2、3 节。

字段名和枚举值是和 Flutter 客户端的约定，改动要先改契约。
"""

from app.i18n import ENGLISH_REFLECTION_PROMPTS, is_reflection_prompt
from datetime import date as date_
from datetime import datetime
from typing import Annotated, Any, Literal, Union

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from app.models import AuditStatus, CheckInSource, EdgeKind, NodePosition, NodeType, SkillStatus


def _not_blank(value: str) -> str:
    stripped = value.strip()
    if not stripped:
        raise ValueError("must not be empty or whitespace-only")
    return stripped


class _Out(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# ---------------------------------------------------------------- 课程

class ClarifyRequest(BaseModel):
    topic: str

    _validate_topic = field_validator("topic")(_not_blank)


class ClarifyResponse(BaseModel):
    needs_clarification: bool
    questions: list[str]


class ScoutRequest(BaseModel):
    answer: str = Field(max_length=120)

    _validate_answer = field_validator("answer")(_not_blank)


class ScoutOptionOut(BaseModel):
    topic: str
    why: str


class ScoutResponse(BaseModel):
    """`clear`: build `topic`. `choose`: show `question` and let the player pick one of `options`."""

    kind: Literal["clear", "choose"]
    topic: str = ""
    question: str = ""
    options: list[ScoutOptionOut] = []


class GenerateCourseRequest(BaseModel):
    topic: str
    # No node count or depth: a course is as big as its topic, down to one model / method /
    # concept per leaf, and is generated in layers (POST /skills/{id}/expand).
    difficulty: Literal["intro", "standard", "deep"] = "standard"
    # 关掉可以省一次搜索加一次 LLM 调用；离线演示和不想联网时用。
    search_syllabus: bool = True

    _validate_topic = field_validator("topic")(_not_blank)


class CourseOut(_Out):
    id: int
    topic: str
    source_course: str | None
    source_url: str | None
    created_at: datetime


class SkillNodeOut(_Out):
    id: int
    course_id: int
    slug: str
    title: str
    description: str
    status: SkillStatus
    node_type: NodeType
    mastery_score: int | None
    unexpanded: bool = False
    tested_out: bool = False

    @field_validator("unexpanded", "tested_out", mode="before")
    @classmethod
    def _null_is_false(cls, value):
        return bool(value)


class SkillEdgeOut(_Out):
    from_id: int
    to_id: int
    kind: EdgeKind
    is_primary: bool | None
    reason: str | None


class CourseGraphOut(BaseModel):
    """Used by both POST /skills/generate and GET /courses/{id}/map."""

    course: CourseOut
    nodes: list[SkillNodeOut]
    edges: list[SkillEdgeOut]


class RecommendationOut(BaseModel):
    context_bucket: str
    suggested_tier: str
    # JSON 对象的键只能是字符串；序列化时 int 键会变成 "5" 这样的字符串。
    skill_tiers: dict[int, str]


# ---------------------------------------------------------------- 审计

class StartAuditRequest(BaseModel):
    mode: Literal["day", "night"] = "day"
    # Challenge a whole branch (or the course): pass it and everything under it is mastered.
    test_out: bool = False


class AuditTurnOut(BaseModel):
    role: Literal["user", "auditor"]
    content: str


class AuditSessionOut(BaseModel):
    id: int
    skill_id: int
    node_position: NodePosition
    status: AuditStatus
    score: int | None
    gaps: list[str]
    comment: str | None
    turns: list[AuditTurnOut]
    test_out: bool = False


class StartAuditResponse(BaseModel):
    session: AuditSessionOut
    opening_question: str


class SubmitTurnRequest(BaseModel):
    content: str

    _validate_content = field_validator("content")(_not_blank)


class ProbeResult(BaseModel):
    """A probe carries only `type` and `question`; a Challenger overturn looks the same."""

    type: Literal["probe"] = "probe"
    question: str


class VerdictResult(BaseModel):
    type: Literal["verdict"] = "verdict"
    passed: bool
    score: int
    gaps: list[str]
    comment: str
    unlocked_skill_ids: list[int]
    # 通过时有值，失败时为 null。
    reward_amount: int | None
    reward_multiplier: float | None


TurnResult = Annotated[Union[ProbeResult, VerdictResult], Field(discriminator="type")]


class ReflectionRequest(BaseModel):
    reflection: str

    _validate_reflection = field_validator("reflection")(_not_blank)


class PrincipleOut(BaseModel):
    id: int
    title: str
    body: str
    misconception: str | None
    source_session_id: int
    # 来源审计所针对的节点。
    skill_id: int
    skill_title: str
    created_at: datetime


# ---------------------------------------------------------------- 知识图谱

class GraphNodeOut(BaseModel):
    id: str  # "skill:5" | "principle:7"
    kind: Literal["skill", "principle"]
    title: str
    status: SkillStatus | None = None
    node_type: NodeType | None = None
    course_id: int | None = None


class GraphEdgeOut(BaseModel):
    source: str
    target: str
    kind: Literal["contains", "requires", "origin", "related", "contradicts"]
    reason: str | None = None


class GraphResponse(BaseModel):
    nodes: list[GraphNodeOut]
    edges: list[GraphEdgeOut]


# ---------------------------------------------------------------- 签到、画像、简报、学习计划

# The five a check-in asks about (a follow-up names the missing ones).
CHECKIN_FIELDS = ("sleep_hours", "exercised", "diet_note", "focus", "stress")
# Kept for trends when given, never asked for.
EXTRA_CHECKIN_FIELDS = ("sleep_quality", "exercise_minutes", "weight_kg")
ALL_CHECKIN_FIELDS = CHECKIN_FIELDS + EXTRA_CHECKIN_FIELDS


class CheckInRequest(BaseModel):
    """Voice (`transcript`) or manual (any subset of the fields). A transcript wins."""

    transcript: str | None = None
    sleep_hours: int | None = Field(default=None, ge=0, le=14)
    exercised: bool | None = None
    diet_note: str | None = None
    focus: int | None = Field(default=None, ge=1, le=5)
    stress: int | None = Field(default=None, ge=1, le=5)
    sleep_quality: int | None = Field(default=None, ge=1, le=5)
    exercise_minutes: int | None = Field(default=None, ge=0, le=600)
    weight_kg: float | None = Field(default=None, ge=20, le=400)

    @field_validator("transcript")
    @classmethod
    def _transcript_not_blank(cls, value: str | None) -> str | None:
        return None if value is None else _not_blank(value)

    @field_validator("diet_note")
    @classmethod
    def _clean_diet_note(cls, value: str | None) -> str | None:
        return (value.strip() or None) if value is not None else None

    @model_validator(mode="after")
    def _needs_something(self):
        if self.transcript is None and all(getattr(self, f) is None for f in ALL_CHECKIN_FIELDS):
            raise ValueError("a transcript or at least one field is required")
        return self


class DailyCheckInOut(_Out):
    date: date_
    sleep_hours: int | None
    exercised: bool | None
    diet_note: str | None
    focus: int | None
    stress: int | None
    transcript: str | None
    source: CheckInSource
    sleep_quality: int | None = None
    exercise_minutes: int | None = None
    weight_kg: float | None = None


class CheckInEdit(BaseModel):
    """PUT /checkins/{date}: the fields sent replace the day's (null clears one); the others stay."""

    sleep_hours: int | None = Field(default=None, ge=0, le=14)
    exercised: bool | None = None
    diet_note: str | None = Field(default=None, max_length=200)
    focus: int | None = Field(default=None, ge=1, le=5)
    stress: int | None = Field(default=None, ge=1, le=5)
    sleep_quality: int | None = Field(default=None, ge=1, le=5)
    exercise_minutes: int | None = Field(default=None, ge=0, le=600)
    weight_kg: float | None = Field(default=None, ge=20, le=400)

    @field_validator("diet_note")
    @classmethod
    def _clean_diet_note(cls, value: str | None) -> str | None:
        return (value.strip() or None) if value is not None else None


class LifeDayOut(BaseModel):
    """One calendar day of the life overview: its check-in (nulls without one) and its audits."""

    date: date_
    checked_in: bool
    sleep_hours: int | None = None
    sleep_quality: int | None = None
    exercised: bool | None = None
    exercise_minutes: int | None = None
    weight_kg: float | None = None
    diet_note: str | None = None
    focus: int | None = None
    stress: int | None = None
    audits: int = 0
    passed: int = 0


class LifeGroupOut(BaseModel):
    days: int
    audits: int
    pass_rate: float | None
    avg_focus: float | None


class LifePatternOut(BaseModel):
    """Two groups of the player's own days compared. Shown once each group has enough days."""

    kind: Literal["sleep", "exercise", "stress"]
    better: LifeGroupOut  # slept 7 h or more / exercised / stress 1-2
    worse: LifeGroupOut  # under 6 h / did not exercise / stress 4-5


class LifeSummaryOut(BaseModel):
    days: int  # the window
    days_logged: int
    avg_sleep_hours: float | None
    avg_sleep_quality: float | None
    exercise_days: int
    avg_exercise_minutes: float | None
    avg_focus: float | None
    avg_stress: float | None
    weight_first: float | None
    weight_last: float | None
    audits: int
    passed: int


class LifeAdviceItemOut(BaseModel):
    title: str
    body: str
    based_on: str


class LifeAdviceOut(BaseModel):
    items: list[LifeAdviceItemOut]
    generated_at: datetime


class LifeOut(BaseModel):
    summary: LifeSummaryOut
    days: list[LifeDayOut]  # every day of the window, oldest first
    patterns: list[LifePatternOut]
    # Days each group needs before a pattern is shown.
    pattern_min_days: int
    advice: LifeAdviceOut | None


class CheckInResponse(BaseModel):
    checkin: DailyCheckInOut
    missing_fields: list[str]


class NodeCounts(BaseModel):
    total: int
    mastered: int
    available: int
    locked: int


class AuditCounts(BaseModel):
    total: int
    passed: int
    failed: int


class MisconceptionClusterOut(BaseModel):
    label: str
    occurrences: int
    skills: list[str]
    cross_skill: bool
    principle_ids: list[int]


class ConditionOut(BaseModel):
    days: int
    avg_sleep_hours: float | None
    avg_stress: float | None
    flag: Literal["low", "normal", "unknown"]


class XpOut(BaseModel):
    """total = sum of all rewards; level and progress come from the mastered-node count."""

    total: int
    level: int
    level_progress: float


class ProfileFacts(BaseModel):
    nodes: NodeCounts
    audits: AuditCounts
    misconception_clusters: list[MisconceptionClusterOut]
    condition: ConditionOut
    # 契约第 5 节新增；给默认值是为了不带 xp 手工构造 ProfileFacts 的调用方（Narrator 测试等）不用改。
    xp: XpOut = XpOut(total=0, level=1, level_progress=0.0)


class Briefing(BaseModel):
    facts: ProfileFacts
    narrative: str | None
    narrative_generated_at: datetime | None


class PlanStepOut(BaseModel):
    skill_id: int
    course_id: int
    skill_title: str
    node_type: NodeType
    rationale: str
    focus_hint: str


class StudyPlanOut(BaseModel):
    id: int
    suggested_tier: str
    context_bucket: str
    created_at: datetime
    steps: list[PlanStepOut]


# ---------------------------------------------------------------- 资料检索（Material Finder）

class SearchPlanRequest(BaseModel):
    """Search needs context: a gap or a misconception id, never a bare topic (AD-5)."""

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


# ---------------------------------------------------------------- 舞台 UI（契约第 5 节）

class ChatRequest(BaseModel):
    message: str
    # Ids from POST /api/uploads; every one must exist (404 `upload not found`).
    upload_ids: list[int] | None = None
    # Answering one of the seven reflection prompts (contract section 6): no LLM runs.
    reflection_prompt: str | None = None
    # Build a course on this topic right away (the tutorial): the front desk is skipped, so
    # nothing depends on how it would classify the message. Blank is allowed with uploads
    # (the topic is then the first file's name).
    course_topic: str | None = Field(default=None, max_length=120)

    _validate_message = field_validator("message")(_not_blank)

    @model_validator(mode="after")
    def _course_needs_a_topic_or_a_file(self) -> "ChatRequest":
        if self.course_topic is not None and not self.course_topic.strip() and not self.upload_ids:
            raise ValueError("course_topic must not be blank without upload_ids")
        return self

    @field_validator("reflection_prompt")
    @classmethod
    def _known_prompt(cls, value: str | None) -> str | None:
        if value is not None and not is_reflection_prompt(value):
            raise ValueError("must be one of the reflection prompts")
        return value


class UploadOut(_Out):
    id: int
    filename: str
    chars: int
    created_at: datetime


class ChatMessageOut(BaseModel):
    id: int
    role: Literal["user", "assistant"]
    content: str
    agent: str | None
    # null 或 {"type": "course" | "checkin" | "plan" | "briefing" | "navigate", ...}，形状见契约。
    action: dict[str, Any] | None
    created_at: datetime


class ChatResponse(BaseModel):
    messages: list[ChatMessageOut]


class ChatActIn(BaseModel):
    """A tool call of the realtime Guide (contract #36)."""

    intent: Literal["generate_course", "open_skill", "checkin", "plan", "briefing", "open_map"]
    args: dict[str, Any] = Field(default_factory=dict)
    # What the user said, in their words; saved as their message.
    said: str = Field("", max_length=4000)


class ChatLine(BaseModel):
    role: Literal["user", "assistant"]
    content: str = Field(max_length=4000)


class ChatLogIn(BaseModel):
    """A spoken exchange with the realtime Guide, kept in the history (contract #36)."""

    messages: list[ChatLine] = Field(max_length=20)


class ChatSuggestionOut(BaseModel):
    label: str
    message: str
    skill_id: int | None
    reflection: bool = False


class ChatSuggestionsResponse(BaseModel):
    suggestions: list[ChatSuggestionOut]


class AuditSummaryOut(BaseModel):
    id: int
    skill_id: int
    skill_title: str
    status: AuditStatus
    score: int | None
    created_at: datetime
    test_out: bool = False


class RequiredSkillOut(BaseModel):
    skill: SkillNodeOut
    reason: str | None


class SkillOverviewOut(BaseModel):
    skill: SkillNodeOut
    course: CourseOut
    contains_parents: list[SkillNodeOut]
    requires: list[RequiredSkillOut]
    audits: list[AuditSummaryOut]
    materials: list[SearchPlanOut]


# ---------------------------------------------------------------- life-as-a-game layer (contract section 6)

# One per KST time window, in window order starting at 03:00. The strings are binding; the
# Chinese and Korean versions are in app/i18n.py.
REFLECTION_PROMPTS: tuple[str, ...] = ENGLISH_REFLECTION_PROMPTS

PROFILE_TEXT_MAX = 280
PROFILE_RULES_MAX = 5
PROFILE_RULE_MAX = 120


def _profile_text(value: str) -> str:
    value = value.strip()
    if len(value) > PROFILE_TEXT_MAX:
        raise ValueError(f"must be at most {PROFILE_TEXT_MAX} characters")
    return value


def _profile_rules(value: list[str]) -> list[str]:
    rules = [r.strip() for r in value if r.strip()]  # blank items are dropped, then the limits apply
    if len(rules) > PROFILE_RULES_MAX:
        raise ValueError(f"at most {PROFILE_RULES_MAX} rules")
    if any(len(r) > PROFILE_RULE_MAX for r in rules):
        raise ValueError(f"each rule must be at most {PROFILE_RULE_MAX} characters")
    return rules


class ProfileOut(BaseModel):
    identity: str
    vision: str
    anti_vision: str
    rules: list[str]
    updated_at: datetime | None
    # The first-run tutorial is done (or skipped); the client shows it until then.
    onboarded: bool = False


class ProfileUpdate(BaseModel):
    """Any subset of the fields; omitted ones are kept (so no defaults, and null is a 422)."""

    identity: str | None = None
    vision: str | None = None
    anti_vision: str | None = None
    rules: list[str] | None = None
    # true: the tutorial is done (stamps the time); false: show it again.
    onboarded: bool | None = None

    @model_validator(mode="after")
    def _no_nulls_and_limits(self):
        # `null` is not "clear it": an explicitly sent null is rejected, an omitted field is kept.
        for name in self.model_fields_set:
            if getattr(self, name) is None:
                raise ValueError(f"{name} must not be null")
        for name in ("identity", "vision", "anti_vision"):
            if name in self.model_fields_set:
                setattr(self, name, _profile_text(getattr(self, name)))
        if "rules" in self.model_fields_set:
            self.rules = _profile_rules(self.rules)
        return self


GOALS_MAX = 3
GOAL_TITLE_MAX = 80


def _goal_title(value: str) -> str:
    value = value.strip()
    if not value:
        raise ValueError("title must not be blank")
    if len(value) > GOAL_TITLE_MAX:
        raise ValueError(f"title must be at most {GOAL_TITLE_MAX} characters")
    return value


class MeOut(BaseModel):
    """GET /api/me (contract #32)."""

    id: str
    email: str | None
    auth_mode: str
    # Sees the developer panel (contract #34).
    is_dev: bool = False


# ---------------------------------------------------------------- developer panel (contract #34)

AuditReview = Literal["right", "too_strict", "too_lenient"]


class DevTurnOut(BaseModel):
    role: str
    content: str


class DevAuditOut(BaseModel):
    id: int
    skill_id: int
    skill_title: str
    status: str
    score: int | None
    gaps: list[str]
    comment: str | None
    turns: list[DevTurnOut]
    review: AuditReview | None
    leaked: bool
    created_at: datetime


class DevMetricsOut(BaseModel):
    """Rates are 0..1 and null when there is nothing to divide by."""

    finished: int
    pass_rate: float | None
    avg_score: float | None
    avg_gaps_when_failed: float | None
    avg_answers: float | None
    challenged_rate: float | None
    reviewed: int
    agreement: float | None
    kappa: float | None
    too_strict: int
    too_lenient: int
    leaked: int


class DevAuditsOut(BaseModel):
    metrics: DevMetricsOut
    audits: list[DevAuditOut]


class AuditReviewIn(BaseModel):
    # null clears the review.
    review: AuditReview | None
    leaked: bool = False


class GoalOut(BaseModel):
    id: int
    title: str
    course_ids: list[int]
    created_at: datetime


class GoalCreate(BaseModel):
    title: str

    @model_validator(mode="after")
    def _title(self):
        self.title = _goal_title(self.title)
        return self


class GoalUpdate(BaseModel):
    """Any subset; omitted fields are kept, an explicit null is a 422."""

    title: str | None = None
    course_ids: list[int] | None = None

    @model_validator(mode="after")
    def _no_nulls(self):
        for name in self.model_fields_set:
            if getattr(self, name) is None:
                raise ValueError(f"{name} must not be null")
        if "title" in self.model_fields_set:
            self.title = _goal_title(self.title)
        if "course_ids" in self.model_fields_set:
            self.course_ids = list(dict.fromkeys(self.course_ids))  # duplicates collapse, order kept
        return self


class JournalEntryOut(_Out):
    id: int
    prompt: str
    answer: str
    created_at: datetime


class VoiceStatusOut(BaseModel):
    # False: no OPENAI_API_KEY; the app uses the device's own speech.
    available: bool


class TranscriptOut(BaseModel):
    text: str


class SpeechIn(BaseModel):
    text: str = Field(min_length=1, max_length=4096)


class VoiceUsageIn(BaseModel):
    """A live voice session's running totals (contract #37)."""

    kind: Literal["guide", "transcribe"]
    model: str = Field("", max_length=64)
    started_at: datetime | None = None
    seconds: float = Field(0, ge=0, le=6 * 3600)
    turns: int = Field(0, ge=0)
    text_in: int = Field(0, ge=0)
    text_in_cached: int = Field(0, ge=0)
    audio_in: int = Field(0, ge=0)
    audio_in_cached: int = Field(0, ge=0)
    text_out: int = Field(0, ge=0)
    audio_out: int = Field(0, ge=0)
    transcribed_seconds: float = Field(0, ge=0)


class DevVoiceSessionOut(BaseModel):
    id: int
    kind: str
    model: str
    started_at: datetime
    minutes: float
    turns: int
    audio_in: int
    audio_out: int
    cached_share: float | None
    # Dollars at list price; live_equivalent: the same minutes on GPT-Live (Guide sessions only).
    cost: float
    live_equivalent: float | None


class DevVoiceTotalsOut(BaseModel):
    guide_sessions: int
    guide_minutes: float
    guide_cost: float
    guide_live_equivalent: float
    guide_cost_per_minute: float | None
    guide_cached_share: float | None
    audit_sessions: int
    audit_minutes: float
    audit_cost: float


class DevVoiceOut(BaseModel):
    totals: DevVoiceTotalsOut
    sessions: list[DevVoiceSessionOut]
