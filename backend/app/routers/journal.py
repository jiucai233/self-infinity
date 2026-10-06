"""GET /api/journal (contract #27). No LLM."""

from fastapi import APIRouter, Depends, Query
from sqlmodel import Session

from app.db import get_session
from app.schemas import JournalEntryOut
from app.services import journal

router = APIRouter(prefix="/api", tags=["journal"])


@router.get("/journal", response_model=list[JournalEntryOut])
def get_journal(limit: int = Query(20, ge=1, le=100), session: Session = Depends(get_session)):
    return journal.list_entries(session, limit)
