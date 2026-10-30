"""The developer panel (contract #34, #37, #47): audits, reviews and metrics, what live voice
costs and what the text agents cost. Only for developers: everyone in dev auth mode (local, no accounts), the emails in
DEV_EMAILS otherwise. No LLM."""

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlmodel import Session

from app.auth import CurrentUser, current_user
from app.config import settings
from app.db import get_session
from app.llm import get_provider
from app.schemas import AuditReviewIn, DevAuditOut, DevAuditsOut, DevLLMOut, DevVoiceOut, RejudgeOut
from app.services import audit_review, llm_usage, rejudge, voice_usage

router = APIRouter(prefix="/api/dev", tags=["dev"])


def is_dev(user: CurrentUser) -> bool:
    if settings.auth_mode == "dev":
        return True
    allowed = {e.strip().lower() for e in settings.dev_emails.split(",") if e.strip()}
    return bool(user.email) and user.email.lower() in allowed


def require_dev(user: CurrentUser = Depends(current_user)) -> None:
    if not is_dev(user):
        raise HTTPException(403, "developers only")


@router.get("/audits", response_model=DevAuditsOut, dependencies=[Depends(require_dev)])
def list_audits(limit: int = Query(50, ge=1, le=200), session: Session = Depends(get_session)):
    metrics, audits = audit_review.dev_audits(session, limit)
    return DevAuditsOut(metrics=metrics, audits=audits)


@router.put("/audits/{audit_id}/review", response_model=DevAuditOut, dependencies=[Depends(require_dev)])
def review_audit(audit_id: int, body: AuditReviewIn, session: Session = Depends(get_session)):
    try:
        return audit_review.review(session, audit_id, body.review, body.leaked)
    except LookupError:
        raise HTTPException(404, "audit session not found") from None
    except audit_review.ReviewError as e:
        raise HTTPException(400, str(e)) from None


@router.get("/voice", response_model=DevVoiceOut, dependencies=[Depends(require_dev)])
def voice_costs(limit: int = Query(50, ge=1, le=200), session: Session = Depends(get_session)):
    return voice_usage.overview(session, limit)


@router.get("/llm", response_model=DevLLMOut, dependencies=[Depends(require_dev)])
def llm_costs(session: Session = Depends(get_session)):
    return llm_usage.overview(session)


@router.get("/rejudge", response_model=RejudgeOut, dependencies=[Depends(require_dev)])
def rejudge_summary(session: Session = Depends(get_session)):
    """How many finished audits the current rules have judged again, and decide otherwise."""
    return rejudge.summary(session)


@router.post("/rejudge", response_model=RejudgeOut, dependencies=[Depends(require_dev)])
def rejudge_batch(limit: int = Query(rejudge.BATCH, ge=1, le=10), session: Session = Depends(get_session)):
    """Judges the next few stale audits again under the current rules (one model call each)."""
    return rejudge.run(session, get_provider("auditor"), limit)
