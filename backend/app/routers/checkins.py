from datetime import date as date_

from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session, select

from app.db import get_session
from app.models import DailyCheckIn
from app.schemas import CheckInRequest, VitalityStateOut
from app.services.vitality import get_or_create_vitality_state, recompute_health_and_cap

router = APIRouter(prefix="/api", tags=["vitality"])


@router.post("/checkins", response_model=VitalityStateOut)
def create_checkin(body: CheckInRequest, session: Session = Depends(get_session)):
    today = date_.today()
    existing = session.exec(select(DailyCheckIn).where(DailyCheckIn.date == today)).first()
    if existing is not None:
        # One check-in per calendar day. Reject rather than silently
        # overwrite so a duplicate submit (e.g. accidental double-tap)
        # doesn't quietly discard the user's first, possibly-considered
        # answer.
        raise HTTPException(400, "今日已签到")

    check_in = DailyCheckIn(
        date=today,
        spending_rating=body.spending_rating,
        activity_rating=body.activity_rating,
        eating_rating=body.eating_rating,
    )
    session.add(check_in)
    session.commit()

    state = recompute_health_and_cap(session)
    return state


@router.get("/vitality", response_model=VitalityStateOut)
def get_vitality(session: Session = Depends(get_session)):
    return get_or_create_vitality_state(session)
