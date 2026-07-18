from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session, select

from app.db import get_session
from app.models import FocusSession
from app.schemas import FocusSessionOut

router = APIRouter(prefix="/api/focus", tags=["focus"])


@router.get("/latest", response_model=FocusSessionOut)
def latest_focus_session(session: Session = Depends(get_session)):
    row = session.exec(select(FocusSession).order_by(FocusSession.started_at.desc())).first()
    if row is None:
        raise HTTPException(404, "no focus sessions recorded yet")
    return row
