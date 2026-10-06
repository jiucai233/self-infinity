"""POST /api/checkins (contract #12) and GET /api/checkins/today (#21).

The recording logic lives in app/services/checkin.py (the chat intent shares it).
"""

from fastapi import APIRouter, Depends
from sqlmodel import Session

from app.db import get_session
from app.llm import get_provider
from app.schemas import CheckInRequest, CheckInResponse, DailyCheckInOut
from app.services import checkin as checkin_service

router = APIRouter(prefix="/api", tags=["checkins"])


@router.post("/checkins", response_model=CheckInResponse)
def create_checkin(body: CheckInRequest, session: Session = Depends(get_session)):
    # Looked up at call time (not bound at import), so the router's `get_provider` can be swapped.
    return checkin_service.record_checkin(session, body, lambda agent: get_provider(agent))


@router.get("/checkins/today", response_model=DailyCheckInOut | None)
def get_today(session: Session = Depends(get_session)):
    """Today's (KST) check-in, or JSON null with 200 when there is none."""
    record = checkin_service.todays_checkin(session)
    return DailyCheckInOut.model_validate(record) if record else None
