"""Lasting facts about the player (contract #40): what the Fact Keeper keeps from check-ins and
chat, and what the player adds, fixes, ends or deletes on the life page.

A fact holds until it is ended (`ended_at`). The keeper never deletes: a fact that changed is
ended and its new row points back at it (`replaces_id`), one that stopped being true is only
ended, so a wrong change can be undone by bringing the old one back. Only the player deletes.

At most MAX_FACTS hold at once. That list, never a day's row, is all the Life Coach is given.

Before the keeper's call, the Decisions API (~0.3 s, input tokens only) answers one question:
does this message say anything lasting? A confident "no" skips the call, which is most
check-ins. Without an OpenAI key, or when it fails or is unsure, the keeper is asked anyway.
"""

import logging
from collections.abc import Callable
from datetime import date

from sqlalchemy.engine import Engine
from sqlmodel import Session, col, select

from app.agents.fact_keeper import Change, FactKeeper, fact_line
from app.llm import decisions, get_provider
from app.llm.base import LLMProvider
from app.models import FactCategory, FactSource, LifeFact, utcnow
from app.schemas import LifeFactEdit, LifeFactIn
from app.utils import local_today

logger = logging.getLogger(__name__)

MAX_FACTS = 20
MAX_PAST_FACTS = 50
CONFIDENT = 0.75

Decide = Callable[[str, list[dict]], dict[str, tuple[str, float]]]

GATE = decisions.choice(
    "lasting",
    "Does the learner's message say something about them that will still hold in a few weeks "
    "(an injury or illness they name, a regular schedule, a period such as exams, something they "
    "cannot do for a while, a stable preference), or that a fact on the list has changed or ended? "
    "One day's sleep, mood, meals or workout is not lasting.",
    [("yes", ""), ("no", "")],
)


class FactNotFound(Exception):
    pass


class FactsFull(Exception):
    """MAX_FACTS facts already hold."""


def current_facts(session: Session) -> list[LifeFact]:
    """What holds now, newest first."""
    return list(
        session.exec(
            select(LifeFact)
            .where(col(LifeFact.ended_at).is_(None))
            .order_by(col(LifeFact.created_at).desc(), col(LifeFact.id).desc())
        ).all()
    )


def past_facts(session: Session, limit: int = MAX_PAST_FACTS) -> list[LifeFact]:
    """Ended facts, most recently ended first."""
    return list(
        session.exec(
            select(LifeFact)
            .where(col(LifeFact.ended_at).is_not(None))
            .order_by(col(LifeFact.ended_at).desc(), col(LifeFact.id).desc())
            .limit(limit)
        ).all()
    )


def for_coach(session: Session) -> list[dict]:
    """The current facts as the Life Coach sees them: category, text and the month they began."""
    return [
        {"category": f.category.value, "text": f.text, "since": f.created_at.strftime("%Y-%m")}
        for f in current_facts(session)
    ]


# ---------------------------------------------------------------- the keeper's changes


def apply_changes(session: Session, changes: list[Change]) -> list[LifeFact]:
    """Applies the keeper's changes in order and returns the rows they made or ended.

    Ids must name a fact that holds now; an add that repeats one, or would go past MAX_FACTS,
    is dropped.
    """
    now = utcnow()
    holding = {f.id: f for f in current_facts(session)}
    touched: list[LifeFact] = []

    def repeats(text: str) -> bool:
        return any(f.text.casefold() == text.casefold() for f in holding.values())

    for change in changes:
        if change.op == "add":
            if change.text is None or repeats(change.text) or len(holding) >= MAX_FACTS:
                continue
            fact = LifeFact(category=change.category or FactCategory.other, text=change.text, created_at=now)
            session.add(fact)
            session.flush()
            holding[fact.id] = fact
            touched.append(fact)
            continue

        old = holding.get(change.fact_id)
        if old is None:
            continue
        old.ended_at = now
        session.add(old)
        del holding[old.id]
        touched.append(old)
        if change.op == "update" and change.text is not None:
            new = LifeFact(
                category=change.category or old.category,
                text=change.text,
                created_at=now,
                replaces_id=old.id,
            )
            session.add(new)
            session.flush()
            holding[new.id] = new
            touched.append(new)
    session.commit()
    return touched


def _worth_asking(said: str, facts: list[LifeFact], decide: Decide | None) -> bool:
    if decide is None:
        return True
    listed = "\n".join(f"- {fact_line(f)}" for f in facts) or "(empty)"
    try:
        answer, confidence = decide(f"Facts on the list:\n{listed}\n\nThe learner said:\n{said}", [GATE])["lasting"]
    except Exception:
        logger.info("fact gate failed, asking the keeper", exc_info=True)
        return True
    return not (answer == "no" and confidence >= CONFIDENT)


def keep_facts(
    session: Session, said: str, provider: LLMProvider, decide: Decide | None = None, today: date | None = None
) -> list[LifeFact]:
    """Reads what the player said and keeps the list up to date. Returns the rows touched."""
    said = said.strip()
    if not said:
        return []
    facts = current_facts(session)
    if not _worth_asking(said, facts, decide):
        return []
    changes = FactKeeper(provider).changes(said, facts, today or local_today(), MAX_FACTS)
    return apply_changes(session, changes)


def run_keeper(
    engine: Engine, said: str, provider_factory: Callable[[], LLMProvider], decide: Decide | None = None
) -> None:
    """Background-task entry point, after the response: opens its own session. Best effort; a
    failure only means the list did not change."""
    try:
        with Session(engine) as session:
            keep_facts(session, said, provider_factory(), decide)
    except Exception:
        logger.warning("fact keeper failed, the facts stay as they were", exc_info=True)


def remember_later(add_task: Callable[..., None], engine: Engine) -> Callable[[str], None]:
    """A `remember(said)` for a request: runs the keeper as a background task (`add_task` is
    FastAPI's BackgroundTasks.add_task), so the reply never waits for it."""

    def remember(said: str) -> None:
        decide = decisions.decide if decisions.available() else None
        add_task(run_keeper, engine, said, lambda: get_provider("fact_keeper"), decide)

    return remember


# ---------------------------------------------------------------- the player's own edits


def add_fact(session: Session, body: LifeFactIn) -> LifeFact:
    if len(current_facts(session)) >= MAX_FACTS:
        raise FactsFull
    fact = LifeFact(category=body.category, text=body.text, source=FactSource.manual)
    session.add(fact)
    session.commit()
    session.refresh(fact)
    return fact


def edit_fact(session: Session, fact_id: int, body: LifeFactEdit) -> LifeFact:
    """A fix of the wording or category is made in place: the fact was written wrong, it did not
    change. `ended` ends it now, or brings an ended one back."""
    fact = session.get(LifeFact, fact_id)
    if fact is None:
        raise FactNotFound(fact_id)
    if body.text is not None:
        fact.text = body.text
    if body.category is not None:
        fact.category = body.category
    if body.ended is True and fact.ended_at is None:
        fact.ended_at = utcnow()
    elif body.ended is False and fact.ended_at is not None:
        if len(current_facts(session)) >= MAX_FACTS:
            raise FactsFull
        fact.ended_at = None
    session.add(fact)
    session.commit()
    session.refresh(fact)
    return fact


def delete_fact(session: Session, fact_id: int) -> None:
    """Gone for good; a fact that replaced it no longer points at it."""
    fact = session.get(LifeFact, fact_id)
    if fact is None:
        raise FactNotFound(fact_id)
    for later in session.exec(select(LifeFact).where(LifeFact.replaces_id == fact_id)).all():
        later.replaces_id = None
        session.add(later)
    session.delete(fact)
    session.commit()
