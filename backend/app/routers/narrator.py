"""GET /api/narrator/briefing (no LLM) and POST /api/narrator/narrate (contract #13, #14)."""

from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session

from app.db import get_session
from app.llm import get_provider
from app.schemas import Briefing
from app.services import briefing as briefing_service
from app.services.briefing import BriefingFailed

router = APIRouter(prefix="/api/narrator", tags=["narrator"])


@router.get("/briefing", response_model=Briefing)
def get_briefing(session: Session = Depends(get_session)):
    return briefing_service.build_briefing(session)


@router.post("/narrate", response_model=Briefing)
def narrate(session: Session = Depends(get_session)):
    try:
        return briefing_service.narrate(session, lambda agent: get_provider(agent))
    except BriefingFailed:
        raise HTTPException(502, "Briefing generation failed. Please try again.")
