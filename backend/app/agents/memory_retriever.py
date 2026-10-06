"""Memory Retriever（纯代码，不调用 LLM）：每次调用 Auditor 之前，挑出用户过去可能相关的教训。

选择规则（plan 7.4）：来源节点是*这个节点*或它的*直接邻居*（contains 或 requires，不分方向）
的教训，再加上 Linker 链接到这个节点的教训；最近的在前，最多 3 条。

这样在 “Quadratic Equations” 学到的教训会在审计 “Quadratic Functions” 时回来——它们之间有一条 requires 边，
或者 Linker 判断过两者相关。最终方法会跟着记忆结构的设计走（plan 5.4、Q-3），所以调用方
只依赖这里的函数签名。
"""

from sqlmodel import Session, col, select

from app.models import AuditSession, LinkTargetKind, Principle, PrincipleLink, SkillNode
from app.services.tree import neighbor_ids

MAX_LESSONS = 3


def retrieve_lessons(session: Session, skill: SkillNode, limit: int = MAX_LESSONS) -> list[Principle]:
    """Most recent first."""
    origin_ids = neighbor_ids(session, skill.id) | {skill.id}

    by_origin = session.exec(
        select(Principle)
        .join(AuditSession, AuditSession.id == Principle.source_session_id)
        .where(col(AuditSession.skill_id).in_(origin_ids))
    ).all()
    linked_ids = session.exec(
        select(PrincipleLink.principle_id).where(
            PrincipleLink.target_kind == LinkTargetKind.skill, PrincipleLink.target_id == skill.id
        )
    ).all()
    linked = session.exec(select(Principle).where(col(Principle.id).in_(linked_ids))).all() if linked_ids else []

    unique = {p.id: p for p in [*by_origin, *linked]}
    ordered = sorted(unique.values(), key=lambda p: (p.created_at, p.id), reverse=True)
    return ordered[:limit]


def recent_misconceptions(session: Session, limit: int) -> list[str]:
    """The user's most recent diagnosed misconceptions, for the Challenger.

    No matching against the current answer here: the Challenger reads the whole dialogue
    and judges whether the explanation fell into one of them again, which text overlap
    cannot do.
    """
    rows = session.exec(
        select(Principle)
        .where(col(Principle.misconception).is_not(None))
        .order_by(col(Principle.created_at).desc(), col(Principle.id).desc())
        .limit(limit)
    ).all()
    return [p.misconception for p in rows if p.misconception]
