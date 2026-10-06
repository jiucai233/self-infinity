"""Linker 的编排：reflection 的响应发出之后，在后台把新教训和已有的东西连起来。

候选由代码挑（≤30 条）：同一门课里的其他教训（最近的在前）和节点（不含这条教训自己的
来源节点——"origin"边已经表达了它）。教训只取一部分名额，留出足够的位置给节点，否则
教训攒多了以后 Linker 就再也连不到节点上，而"教训顺着链接回到相关节点"正是它的用处。

这一步是尽力而为的：任何失败都只意味着没有链接，教训本身早已保存。
"""

import logging
from collections.abc import Callable

from sqlalchemy.engine import Engine
from sqlmodel import Session, col, select

from app.agents.linker import LinkCandidate, Linker
from app.llm.base import LLMProvider
from app.models import AuditSession, LinkKind, LinkTargetKind, Principle, PrincipleLink, SkillNode

logger = logging.getLogger(__name__)

MAX_CANDIDATES = 30
MAX_LESSON_CANDIDATES = 10


def build_candidates(session: Session, principle: Principle) -> list[LinkCandidate]:
    origin = session.get(AuditSession, principle.source_session_id)
    skill = session.get(SkillNode, origin.skill_id) if origin else None
    if skill is None:
        return []

    lessons = session.exec(
        select(Principle)
        .join(AuditSession, AuditSession.id == Principle.source_session_id)
        .join(SkillNode, SkillNode.id == AuditSession.skill_id)
        .where(SkillNode.course_id == skill.course_id, Principle.id != principle.id)
        .order_by(col(Principle.created_at).desc(), col(Principle.id).desc())
        .limit(MAX_LESSON_CANDIDATES)
    ).all()
    candidates = [LinkCandidate("principle", p.id, p.title, p.body) for p in lessons]

    nodes = session.exec(
        select(SkillNode)
        .where(SkillNode.course_id == skill.course_id, SkillNode.id != skill.id)
        .order_by(SkillNode.id)
        .limit(MAX_CANDIDATES - len(candidates))
    ).all()
    candidates += [LinkCandidate("skill", n.id, n.title, n.description) for n in nodes]
    return candidates


def link_principle(session: Session, provider: LLMProvider, principle: Principle) -> int:
    """Ask the Linker and persist its links. Returns how many links were saved."""
    candidates = build_candidates(session, principle)
    if not candidates:
        return 0
    judgment = Linker(provider).link(principle.title, principle.body, principle.misconception, candidates)

    links = [
        PrincipleLink(
            principle_id=principle.id,
            target_kind=LinkTargetKind(candidate.kind),
            target_id=candidate.id,
            kind=LinkKind.related,
            reason=reason,
        )
        for candidate, reason in judgment.related
    ] + [
        PrincipleLink(
            principle_id=principle.id,
            target_kind=LinkTargetKind.principle,
            target_id=candidate.id,
            kind=LinkKind.contradicts,
            reason=reason,
        )
        for candidate, reason in judgment.contradicts
    ]
    session.add_all(links)
    session.commit()
    return len(links)


def run_linker(engine: Engine, provider_factory: Callable[[], LLMProvider], principle_id: int) -> None:
    """Background-task entry point. Opens its own session: the request's is already closed.

    The provider is built here, not by the caller, so that even failing to build it only
    costs the links.
    """
    try:
        with Session(engine) as session:
            principle = session.get(Principle, principle_id)
            if principle is not None:
                link_principle(session, provider_factory(), principle)
    except Exception:
        logger.warning("linker failed, the lesson stays without links", exc_info=True)
