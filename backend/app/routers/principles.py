from fastapi import APIRouter, Depends
from sqlmodel import Session, col, select

from app.db import get_session
from app.models import AuditSession, Principle, PrincipleCheck, SkillNode
from app.schemas import PrincipleOut

router = APIRouter(prefix="/api/principles", tags=["principles"])


@router.get("", response_model=list[PrincipleOut])
def list_principles(session: Session = Depends(get_session)):
    """Newest first, each with the node its source audit was about."""
    rows = session.exec(
        select(Principle, SkillNode)
        .join(AuditSession, AuditSession.id == Principle.source_session_id)
        .join(SkillNode, SkillNode.id == AuditSession.skill_id)
        .order_by(col(Principle.created_at).desc(), col(Principle.id).desc())
    ).all()
    counts = check_counts(session)
    return [principle_out(principle, skill, counts.get(principle.id)) for principle, skill in rows]


def check_counts(session: Session, principle_id: int | None = None) -> dict[int, tuple[int, int]]:
    """Per lesson: (times it held, times the mistake came back) in later audits."""
    query = select(PrincipleCheck)
    if principle_id is not None:
        query = query.where(PrincipleCheck.principle_id == principle_id)
    counts: dict[int, tuple[int, int]] = {}
    for check in session.exec(query).all():
        held, relapsed = counts.get(check.principle_id, (0, 0))
        counts[check.principle_id] = (held + check.held, relapsed + (not check.held))
    return counts


def principle_out(principle: Principle, skill: SkillNode, checks: tuple[int, int] | None = None) -> PrincipleOut:
    held, relapsed = checks or (0, 0)
    return PrincipleOut(
        held=held,
        relapsed=relapsed,
        id=principle.id,
        title=principle.title,
        body=principle.body,
        misconception=principle.misconception,
        source_session_id=principle.source_session_id,
        skill_id=skill.id,
        skill_title=skill.title,
        created_at=principle.created_at,
    )
