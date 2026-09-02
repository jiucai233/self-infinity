from datetime import date as date_
from datetime import datetime, timezone
from enum import StrEnum

from sqlmodel import Field, SQLModel


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def as_utc(dt: datetime) -> datetime:
    """Read a stored timestamp back as timezone-aware UTC.

    SQLite has no tz-aware column type, so values written by utcnow() come
    back naive. Comparing one of those against utcnow() raises TypeError, so
    anything comparing a persisted timestamp to "now" must go through here.
    """
    return dt if dt.tzinfo is not None else dt.replace(tzinfo=timezone.utc)


class SkillStatus(StrEnum):
    locked = "locked"
    available = "available"
    mastered = "mastered"


class NodeType(StrEnum):
    concept = "concept"  # 需要理解为什么成立的知识点 -> 全套费曼审计
    task = "task"  # 一个可执行的具体步骤 -> 只核验有没有做到，不深挖原理


class AuditStatus(StrEnum):
    active = "active"
    passed = "passed"
    failed = "failed"


class TurnRole(StrEnum):
    user = "user"
    auditor = "auditor"


class SkillNode(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    slug: str = Field(index=True, unique=True)
    title: str
    description: str
    parent_id: int | None = Field(default=None, foreign_key="skillnode.id")
    status: SkillStatus = SkillStatus.locked
    node_type: NodeType = NodeType.concept
    mastery_score: int | None = None


class AuditSession(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    skill_id: int = Field(foreign_key="skillnode.id")
    status: AuditStatus = AuditStatus.active
    score: int | None = None
    gaps_json: str | None = None
    comment: str | None = None
    # 会话创建时按 mode + node_type 一次性算出的追问上限，此后终身固定，
    # 不再随全局配置变化而漂移（见 AuditMode / start_audit）。
    max_turns: int = 4
    # 该会话是否已被 Challenger 复核过。复核每场审计最多一次，这个标记就是那道
    # 收敛保证（见 app/agents/challenger.py）。刻意声明为 nullable：_add_missing_columns()
    # 只能给已存在的库追加可空列，NOT NULL 会被它直接拒绝，老数据行读回来是 None，
    # 判断一律走 `not audit.challenged`。
    challenged: bool = Field(default=False, nullable=True)
    created_at: datetime = Field(default_factory=utcnow)


class AuditTurn(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    session_id: int = Field(foreign_key="auditsession.id")
    role: TurnRole
    content: str
    created_at: datetime = Field(default_factory=utcnow)


class Principle(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    title: str
    body: str
    # The underlying wrong mental model the Scribe diagnosed behind this
    # failure (teach-me-style misconception tracking) — distinct from `body`,
    # which is the corrective rule. Used to detect recurring failure
    # patterns across unrelated skills (see find_recurring_misconception).
    misconception: str | None = None
    source_session_id: int = Field(foreign_key="auditsession.id")
    created_at: datetime = Field(default_factory=utcnow)


class LinkKind(StrEnum):
    related = "related"
    contradicts = "contradicts"


class LinkTargetKind(StrEnum):
    skill = "skill"
    principle = "principle"


class PrincipleLink(SQLModel, table=True):
    # LLM-judged relationship from a Principle to another node (a skill it
    # applies to, or another principle it agrees or conflicts with) —
    # replaces the old keyword-overlap heuristic that used to be computed
    # live on every /api/graph request. Persisted once (at principle
    # creation, or in bulk via the /api/graph/relink lint pass) so the
    # judgment doesn't need re-running per request. Undirected in practice:
    # one row is enough to render the edge either way in the graph UI.
    id: int | None = Field(default=None, primary_key=True)
    principle_id: int = Field(foreign_key="principle.id")
    target_kind: LinkTargetKind
    target_id: int
    kind: LinkKind
    reason: str
    created_at: datetime = Field(default_factory=utcnow)


class BanditArm(SQLModel, table=True):
    # Beta-Bernoulli posterior for one (context_bucket, difficulty tier) arm
    # of the whitepaper §4.4 V2.1 contextual bandit — see
    # app/services/bandit.py for the discretization rationale. alpha/beta
    # start at 1.0 (uniform prior) and shift with each observed audit
    # outcome for that arm; there's no user-facing CRUD for this table.
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
    created_at: datetime = Field(default_factory=utcnow)


class DailyCheckIn(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    date: date_ = Field(index=True, unique=True)
    spending_rating: int
    activity_rating: int
    eating_rating: int


class VitalityState(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    health: float
    sanity: float
    sanity_cap: float
    updated_at: datetime = Field(default_factory=utcnow)


class FocusSession(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    started_at: datetime = Field(default_factory=utcnow)
    ended_at: datetime | None = None
    focus_score: int | None = None
    # source is intentionally free-text (e.g. "audit_engagement"), not tied
    # to desktop screen-capture monitoring, which was deferred per §3 ADRs.
    source: str


class NarratorBriefing(SQLModel, table=True):
    """Narrator 最近一次生成的叙述。

    只保留历史记录，读取时取最新一条。缓存的理由是成本与延迟：画像本身是纯 DB 计算
    可以随便刷，但把它讲成话要调一次 LLM——首屏每次打开都调既慢又烧钱，所以叙述
    只在用户主动点"重新生成"时更新。
    """

    id: int | None = Field(default=None, primary_key=True)
    narrative: str
    generated_at: datetime = Field(default_factory=utcnow)


class StudyPlan(SQLModel, table=True):
    """Planner 生成的一份短期学习顺序。

    落库而不是每次现算：一次规划要调一次 LLM，而用户会反复打开这个页面。context_json
    存的是生成当时的状态快照（难度档位、体力等），这样计划旧了之后能看出它是基于
    什么判断做出来的——一份没有前提的计划无法判断还该不该信。
    """

    id: int | None = Field(default=None, primary_key=True)
    steps_json: str
    context_json: str
    created_at: datetime = Field(default_factory=utcnow)


class SearchPlan(SQLModel, table=True):
    """针对某个技能点上某个具体缺口检索到的补救材料。

    落库的理由一半是省钱（一次检索是两次 LLM 调用加若干次搜索 API），一半是它本身
    就是记录：这个缺口当时是靠哪些材料补的，日后复发时能对照着看上次的补救有没有生效。
    """

    id: int | None = Field(default=None, primary_key=True)
    skill_id: int = Field(foreign_key="skillnode.id")
    gap: str
    queries_json: str
    items_json: str
    created_at: datetime = Field(default_factory=utcnow)
