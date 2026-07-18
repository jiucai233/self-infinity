from fastapi import APIRouter, Depends
from sqlmodel import Session, select

from app.db import get_session
from app.models import Principle
from app.schemas import PrincipleOut

router = APIRouter(prefix="/api/principles", tags=["principles"])


@router.get("", response_model=list[PrincipleOut])
def list_principles(session: Session = Depends(get_session)):
    rows = session.exec(select(Principle).order_by(Principle.created_at.desc())).all()
    return rows
