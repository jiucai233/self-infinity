"""数据库模型，对应开发计划第 5 节。

约定：
- 所有时间戳都是带时区的 UTC。SQLite 没有带时区的列类型，裸 datetime 读回来会丢掉
  时区，序列化出去就没有偏移量，所以统一走 UTCDateTime 把它补回来。
- 日历日期（DailyCheckIn.date）按 APP_TIMEZONE 计算，不在这里处理。
"""

from datetime import date as date_
from datetime import datetime, timezone
from enum import StrEnum

from sqlalchemy import DateTime, Index, UniqueConstraint
from sqlalchemy.types import TypeDecorator
from sqlmodel import Field, SQLModel


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def as_utc(dt: datetime) -> datetime:
    """Treat a naive timestamp as UTC.

    UTCDateTime already does this for everything read from the database; this
    is for values that never went through it (hand-built objects in tests).
    """
    return dt if dt.tzinfo is not None else dt.replace(tzinfo=timezone.utc)


class UTCDateTime(TypeDecorator):
    """Stores UTC, always returns timezone-aware UTC."""

    impl = DateTime(timezone=True)
    cache_ok = True

    def process_bind_param(self, value, dialect):
        if value is None:
            return None
        return as_utc(value).astimezone(timezone.utc)

    def process_result_value(self, value, dialect):
        if value is None:
            return None
        return as_utc(value)


class SkillStatus(StrEnum):
    locked = "locked"
    available = "available"
    mastered = "mastered"


class NodeType(StrEnum):
    concept = "concept"  # 需要理解为什么成立的知识点 -> 全套费曼审计
    task = "task"  # 一个可执行的具体步骤 -> 核验计划能不能执行


class EdgeKind(StrEnum):
    contains = "contains"  # from 是父，to 是子：分组、解锁、节点位置
    requires = "requires"  # from 先学，to 后学：只影响推荐顺序，从不锁住节点


class NodePosition(StrEnum):
    root = "root"
    branch = "branch"
    leaf = "leaf"


class AuditStatus(StrEnum):
    active = "active"
    passed = "passed"
    failed = "failed"


class TurnRole(StrEnum):
    user = "user"
    auditor = "auditor"


class LinkKind(StrEnum):
    related = "related"
    contradicts = "contradicts"


class LinkTargetKind(StrEnum):
    skill = "skill"
    principle = "principle"


class CheckInSource(StrEnum):
    voice = "voice"
    manual = "manual"


class Course(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    # 用户输入的主题，连同澄清问题的回答（"{topic}\n\nQ: ...\nA: ..."）。
    topic: str
    settings_json: str = "{}"
    # 找到可信课纲时 course 和 url 同时有值（url 必须来自搜索结果）；用上传文件生成的课程只有
    # source_course（文件名），source_url 为空。所以 source_url 有值时 source_course 一定有值，反之不成立。
    source_course: str | None = None
    source_url: str | None = None
    created_at: datetime = Field(default_factory=utcnow, sa_type=UTCDateTime)
    # Set when the course was deleted keeping its nodes (app/services/courses.py): it is hidden
    # everywhere, its nodes and their history stay.
    archived_at: datetime | None = Field(default=None, sa_type=UTCDateTime)


class SkillNode(SQLModel, table=True):
    # 节点不跨课程共享，所以 slug 只需在课程内唯一；父子关系全部在 SkillEdge 里，
    # 这里刻意没有 parent_id（一个节点可以有最多 3 个 contains 父节点）。
    __table_args__ = (UniqueConstraint("course_id", "slug", name="uq_skillnode_course_slug"),)

    id: int | None = Field(default=None, primary_key=True)
    course_id: int = Field(foreign_key="course.id", index=True)
    slug: str
    title: str
    description: str
    status: SkillStatus = SkillStatus.locked
    node_type: NodeType = NodeType.concept
    mastery_score: int | None = None


class SkillEdge(SQLModel, table=True):
    __table_args__ = (
        UniqueConstraint("from_id", "to_id", "kind", name="uq_skilledge_from_to_kind"),
        Index("ix_skilledge_to_kind", "to_id", "kind"),
        Index("ix_skilledge_from_kind", "from_id", "kind"),
    )

    id: int | None = Field(default=None, primary_key=True)
    from_id: int = Field(foreign_key="skillnode.id")
    to_id: int = Field(foreign_key="skillnode.id")
    kind: EdgeKind
    # 只对 contains 有意义：True 是主父节点（布局用），其余 False；requires 为 NULL。
    is_primary: bool | None = None
    reason: str | None = None
    created_at: datetime = Field(default_factory=utcnow, sa_type=UTCDateTime)


class AuditSession(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    skill_id: int = Field(foreign_key="skillnode.id", index=True)
    # 会话开始时的快照，之后课程结构变了这条记录也不跟着变。
    node_position: NodePosition = NodePosition.leaf
    status: AuditStatus = AuditStatus.active
    score: int | None = None
    gaps_json: str | None = None
    comment: str | None = None
    # 创建时按 mode + node_type 一次性算出，此后固定；它只是服务端的安全阀，
    # 绝不写进给模型的 prompt。
    max_turns: int = 8
    # 复核每场审计最多一次，这个标记就是那道收敛保证（见 app/agents/challenger.py）。
    challenged: bool = False
    # A developer's review of the verdict in the developer panel (app/routers/dev.py):
    # right / too_strict (failed, should have passed) / too_lenient (passed, should have failed).
    review: str | None = None
    # The developer saw the Auditor give the answer away.
    review_leaked: bool | None = None
    created_at: datetime = Field(default_factory=utcnow, sa_type=UTCDateTime)


class AuditTurn(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    session_id: int = Field(foreign_key="auditsession.id", index=True)
    role: TurnRole
    content: str
    created_at: datetime = Field(default_factory=utcnow, sa_type=UTCDateTime)


class Principle(SQLModel, table=True):
    # 追加写入，应用从不更新或删除（AD-4）：旧的 misconception 是学习记录，不是过期数据。
    id: int | None = Field(default=None, primary_key=True)
    title: str
    body: str
    misconception: str | None = None
    source_session_id: int = Field(foreign_key="auditsession.id", index=True)
    created_at: datetime = Field(default_factory=utcnow, sa_type=UTCDateTime)


class PrincipleLink(SQLModel, table=True):
    # Linker 判断出的关系。contradicts 只会指向 principle。
    id: int | None = Field(default=None, primary_key=True)
    principle_id: int = Field(foreign_key="principle.id", index=True)
    target_kind: LinkTargetKind
    target_id: int
    kind: LinkKind
    reason: str = ""
    created_at: datetime = Field(default_factory=utcnow, sa_type=UTCDateTime)

    __table_args__ = (Index("ix_principlelink_target", "target_kind", "target_id"),)


class BanditArm(SQLModel, table=True):
    # Beta-Bernoulli posterior for one (context_bucket, difficulty tier) arm
    # of the contextual bandit — see app/services/bandit.py. alpha/beta start
    # at 1.0 (uniform prior); there's no user-facing CRUD for this table.
    id: int | None = Field(default=None, primary_key=True)
    context_bucket: str
    tier: str
    alpha: float = 1.0
    beta: float = 1.0


class RewardEvent(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    session_id: int = Field(foreign_key="auditsession.id")
    amount: int
    multiplier: float
    created_at: datetime = Field(default_factory=utcnow, sa_type=UTCDateTime)


class DailyCheckIn(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    # 每天一行，按 APP_TIMEZONE 的日历日期（默认 KST）。
    date: date_ = Field(index=True, unique=True)
    sleep_hours: int | None = None
    exercised: bool | None = None
    diet_note: str | None = None
    focus: int | None = None
    stress: int | None = None
    transcript: str | None = None
    source: CheckInSource = CheckInSource.manual
    created_at: datetime = Field(default_factory=utcnow, sa_type=UTCDateTime)


class NarratorBriefing(SQLModel, table=True):
    """Narrator 最近一次生成的叙述，历史保留，读取时取最新一条。"""

    id: int | None = Field(default=None, primary_key=True)
    narrative: str
    generated_at: datetime = Field(default_factory=utcnow, sa_type=UTCDateTime)


class StudyPlan(SQLModel, table=True):
    """Recommender 生成的一份学习顺序，连同生成时的状态快照。"""

    id: int | None = Field(default=None, primary_key=True)
    steps_json: str
    context_json: str
    created_at: datetime = Field(default_factory=utcnow, sa_type=UTCDateTime)


class SearchPlan(SQLModel, table=True):
    """Material Finder 针对某个技能点上某个具体缺口检索到的材料。"""

    id: int | None = Field(default=None, primary_key=True)
    skill_id: int = Field(foreign_key="skillnode.id")
    gap: str
    queries_json: str
    items_json: str
    created_at: datetime = Field(default_factory=utcnow, sa_type=UTCDateTime)


class ChatMessage(SQLModel, table=True):
    """前台对话的一条消息（契约第 5 节）。审计轮次不是 ChatMessage，它们在 AuditTurn 里。"""

    id: int | None = Field(default=None, primary_key=True)
    role: str  # "user" | "assistant"
    content: str
    # 只有 assistant 消息有值：front_desk / narrator / recommender / planner / checkin_converter。
    agent: str | None = None
    # 已序列化好的 action JSON（生成时的快照），没有则为 NULL。
    action_json: str | None = None
    created_at: datetime = Field(default_factory=utcnow, sa_type=UTCDateTime)


class Upload(SQLModel, table=True):
    """A file the user attached in chat (contract endpoint 24): only its extracted text is kept."""

    id: int | None = Field(default=None, primary_key=True)
    filename: str
    text: str  # already cut to MAX_UPLOAD_TEXT_CHARS
    created_at: datetime = Field(default_factory=utcnow, sa_type=UTCDateTime)


class Profile(SQLModel, table=True):
    """The player's own rules of the game (contract section 6): identity, vision, anti-vision, rules.

    Single row: id is always 1. `rules_json` is a JSON list of strings.
    """

    id: int | None = Field(default=None, primary_key=True)
    identity: str = ""
    vision: str = ""
    anti_vision: str = ""
    rules_json: str = "[]"
    # NULL until the first save.
    updated_at: datetime | None = Field(default=None, sa_type=UTCDateTime)
    # When the first-run tutorial was finished or skipped (contract section 7); NULL = not yet.
    onboarded_at: datetime | None = Field(default=None, sa_type=UTCDateTime)


class JournalEntry(SQLModel, table=True):
    """One answered reflection prompt (contract section 6)."""

    id: int | None = Field(default=None, primary_key=True)
    prompt: str
    answer: str
    created_at: datetime = Field(default_factory=utcnow, sa_type=UTCDateTime)


class Goal(SQLModel, table=True):
    """A main quest: a one-year goal the player picks (contract section 6, endpoints 28-31).

    Courses hang under at most one goal; `course_ids_json` is a JSON list of course ids, in the
    order they were attached. A course under no goal is a side quest.
    """

    id: int | None = Field(default=None, primary_key=True)
    title: str
    course_ids_json: str = "[]"
    created_at: datetime = Field(default_factory=utcnow, sa_type=UTCDateTime)
