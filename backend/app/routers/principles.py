from fastapi import APIRouter, Depends
from sqlmodel import Session, col, select

from app.db import get_session
from app.models import AuditSession, Principle, SkillNode
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
    return [principle_out(principle, skill) for principle, skill in rows]


def principle_out(principle: Principle, skill: SkillNode) -> PrincipleOut:
    return PrincipleOut(
        id=principle.id,
        title=principle.title,
        body=principle.body,
        misconception=principle.misconception,
        source_session_id=principle.source_session_id,
        skill_id=skill.id,
        skill_title=skill.title,
        created_at=principle.created_at,
    )
