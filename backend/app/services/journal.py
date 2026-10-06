"""Reflection prompts and the journal (contract section 6, endpoints 20/18/27). No LLM.

The prompt on offer depends on the KST time of day. The clock is `app.utils.local_now`, looked up
at call time so tests can freeze it.
"""

from dataclasses import dataclass
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

from sqlmodel import Session, col, select

from app import utils
from app.config import settings
from app.models import JournalEntry
from app.schemas import REFLECTION_PROMPTS

# (start minute of the KST day, prompt). Each window runs until the next start; the last one
# (21:00) runs through midnight until 02:59, and 00:00-02:59 belongs to the previous day's evening.
_WINDOW_STARTS = (3 * 60, 11 * 60, 13 * 60 + 30, 15 * 60 + 15, 17 * 60, 19 * 60 + 30, 21 * 60)
WINDOWS = tuple(zip(_WINDOW_STARTS, REFLECTION_PROMPTS, strict=True))
_DAY_STARTS_AT = 3 * 60  # the evening window wraps midnight, so its "day" turns over at 03:00


@dataclass(frozen=True)
class ReflectionWindow:
    prompt: str
    day: date  # the KST date the window started on (after midnight: still the previous date)
    wraps_midnight: bool


def current_window(now: datetime | None = None) -> ReflectionWindow:
    now = now or utils.local_now()
    minutes = now.hour * 60 + now.minute
    if minutes < _DAY_STARTS_AT:
        return ReflectionWindow(WINDOWS[-1][1], now.date() - timedelta(days=1), True)
    prompt = [p for start, p in WINDOWS if start <= minutes][-1]
    return ReflectionWindow(prompt, now.date(), prompt == WINDOWS[-1][1])


def _answered_between(window: ReflectionWindow) -> tuple[datetime, datetime]:
    """[start, end) in which an entry with the window's prompt counts as "today".

    A plain KST calendar day, except for the evening window, whose day is 03:00 to 03:00 so that
    an answer given at 01:00 is not mistaken for the next evening's.
    """
    tz = ZoneInfo(settings.app_timezone)
    start = datetime.combine(window.day, time(3) if window.wraps_midnight else time(0), tzinfo=tz)
    return start, start + timedelta(days=1)


def current_prompt(session: Session) -> str | None:
    """The prompt of the current window, or None when it was already answered in this window today."""
    window = current_window()
    start, end = _answered_between(window)
    answered = session.exec(
        select(JournalEntry.id).where(
            JournalEntry.prompt == window.prompt,
            JournalEntry.created_at >= start,
            JournalEntry.created_at < end,
        )
    ).first()
    return None if answered is not None else window.prompt


def add_entry(session: Session, prompt: str, answer: str) -> JournalEntry:
    # Stamped by the same clock that decides which window it answers, not the wall clock.
    entry = JournalEntry(prompt=prompt, answer=answer, created_at=utils.local_now().astimezone(timezone.utc))
    session.add(entry)
    session.commit()
    session.refresh(entry)
    return entry


def list_entries(session: Session, limit: int) -> list[JournalEntry]:
    """Newest first."""
    return list(
        session.exec(
            select(JournalEntry).order_by(col(JournalEntry.created_at).desc(), col(JournalEntry.id).desc()).limit(limit)
        ).all()
    )
