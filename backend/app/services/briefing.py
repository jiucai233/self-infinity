"""The briefing (contract #13, #14): fresh facts plus the cached latest narrative."""

import logging
from collections.abc import Callable

from sqlmodel import Session, col, select

from app.agents.narrator import Narrator
from app.llm.base import LLMProvider
from app.models import NarratorBriefing
from app.schemas import Briefing
from app.services.profile import build_profile

logger = logging.getLogger(__name__)


class BriefingFailed(Exception):
    """The Narrator could not produce a briefing."""


def build_briefing(session: Session) -> Briefing:
    """Fresh facts plus the latest cached narrative (null before the first narration)."""
    latest = session.exec(
        select(NarratorBriefing).order_by(col(NarratorBriefing.generated_at).desc(), col(NarratorBriefing.id).desc())
    ).first()
    return Briefing(
        facts=build_profile(session),
        narrative=latest.narrative if latest else None,
        narrative_generated_at=latest.generated_at if latest else None,
    )


def narrate(session: Session, provider_for: Callable[[str], LLMProvider]) -> Briefing:
    facts = build_profile(session)
    try:
        narrative = Narrator(provider_for("narrator")).narrate(facts)
    except Exception as exc:
        logger.warning("narrator failed", exc_info=True)
        raise BriefingFailed from exc
    session.add(NarratorBriefing(narrative=narrative))
    session.commit()
    return build_briefing(session)
