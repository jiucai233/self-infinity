"""The life overview and the Life Coach (contract #39), and editing a day's check-in."""

import logging
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlmodel import Session

from app.agents.life_coach import LifeCoach
from app.db import get_session
from app.llm import get_provider
from app.schemas import CheckInEdit, DailyCheckInOut, LifeAdviceItemOut, LifeAdviceOut, LifeOut
from app.services import checkin as checkin_service
from app.services import life

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api", tags=["life"])


@router.get("/life", response_model=LifeOut)
def get_life(days: int = Query(30, ge=7, le=365), session: Session = Depends(get_session)):
    """No LLM: the window's days, its summary, the player's own patterns and the latest advice."""
    return life.overview(session, days)


@router.post("/life/advice", response_model=LifeAdviceOut)
def create_advice(session: Session = Depends(get_session)):
    """The Life Coach's three pieces of advice, from coarse facts of the last 14 days; saved."""
    facts = life.coach_facts(session)
    try:
        advice = LifeCoach(get_provider("life_coach")).advise(facts.facts)
    except Exception:
        logger.warning("life coach failed", exc_info=True)
        raise HTTPException(502, "Advice is not available right now. Please try again.") from None
    items = [LifeAdviceItemOut(title=a.title, body=a.body, based_on=a.based_on) for a in advice]
    return life.save_advice(session, items, facts)


@router.put("/checkins/{day}", response_model=DailyCheckInOut)
def edit_checkin(day: date, body: CheckInEdit, session: Session = Depends(get_session)):
    """Fixes or fills in one day: the fields sent replace that day's (null clears one)."""
    try:
        record = checkin_service.edit_checkin(session, day, body)
    except checkin_service.FutureDate:
        raise HTTPException(400, "That day has not come yet.") from None
    return DailyCheckInOut.model_validate(record)
