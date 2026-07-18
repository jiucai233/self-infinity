from datetime import datetime, timezone
from enum import StrEnum

from sqlmodel import Field, SQLModel


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


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
    source_session_id: int = Field(foreign_key="auditsession.id")
    created_at: datetime = Field(default_factory=utcnow)
