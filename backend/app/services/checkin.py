"""Recording a daily check-in (contract #12) and reading today's (#21).

Shared by POST /api/checkins, the chat `checkin` intent and the voice Guide, so all go through
the same Check-in Converter flow. One row per KST calendar day. Said check-ins come in pieces
over a day ("slept 11 to 7" in the morning, "ran 20 minutes" at night), so a said one fills in
the day: the fields it found overwrite, the others stay. A manual (structured) one replaces the
day. A field is never copied from an earlier day.

The voice Guide is asked to call its check-in tool, but a realtime model does not always do it.
`said_later` is the backstop for the lines it only talked about: after the response, the
Decisions API asks whether they report the day, and a yes runs the converter; nothing is saved
when it finds no field.
"""

import logging
from collections.abc import Callable
from datetime import date

from sqlalchemy.engine import Engine
from sqlmodel import Session, select

from app.agents.checkin_converter import CheckinConverter, ConvertedCheckin
from app.llm import decisions, get_provider
from app.llm.base import LLMProvider
from app.models import CheckInSource, DailyCheckIn, utcnow
from app.schemas import ALL_CHECKIN_FIELDS, CHECKIN_FIELDS, CheckInEdit, CheckInRequest, CheckInResponse, DailyCheckInOut
from app.utils import local_today

logger = logging.getLogger(__name__)

CONFIDENT = 0.75
DAILY_GATE = decisions.choice(
    "daily",
    "Does the learner say how their day or last night went: hours or times slept, sleep quality, "
    "exercise, what they ate, their focus, stress or weight? Plans, wishes and other people do not count.",
    [("yes", ""), ("no", "")],
)

Decide = Callable[[str, list[dict]], dict[str, tuple[str, float]]]


class FutureDate(Exception):
    """A check-in for a day that has not come yet."""


def record_checkin(
    session: Session, body: CheckInRequest, provider_for: Callable[[str], LLMProvider]
) -> CheckInResponse:
    today = local_today()
    if body.transcript is not None:
        # The converter never raises (a failure means all fields null), but getting the
        # provider can fail too, so that is inside the same net.
        try:
            converted = CheckinConverter(provider_for("checkin_converter")).convert(body.transcript, today)
        except Exception:
            converted = ConvertedCheckin()
        record = _fill_in(session, today, converted, body.transcript)
    else:
        record = session.exec(select(DailyCheckIn).where(DailyCheckIn.date == today)).first()
        if record is None:
            record = DailyCheckIn(date=today)
        for name in ALL_CHECKIN_FIELDS:
            setattr(record, name, getattr(body, name))
        record.transcript = None
        record.source = CheckInSource.manual
        record.created_at = utcnow()
        session.add(record)
        session.commit()
        session.refresh(record)

    return CheckInResponse(
        checkin=DailyCheckInOut.model_validate(record),
        missing_fields=[f for f in CHECKIN_FIELDS if getattr(record, f) is None],
    )


def _fill_in(session: Session, day: date, converted: ConvertedCheckin, transcript: str) -> DailyCheckIn:
    """A said check-in: what it found overwrites, the rest of the day stays."""
    record = session.exec(select(DailyCheckIn).where(DailyCheckIn.date == day)).first()
    if record is None:
        record = DailyCheckIn(date=day)
    for name in ALL_CHECKIN_FIELDS:
        value = getattr(converted, name)
        if value is not None:
            setattr(record, name, value)
    # The client's follow-up re-sends the earlier words with the answer: keep them once.
    earlier = record.transcript
    record.transcript = transcript if not earlier or transcript.startswith(earlier) else f"{earlier}\n{transcript}"
    record.source = CheckInSource.voice
    record.created_at = utcnow()
    session.add(record)
    session.commit()
    session.refresh(record)
    return record


def found_anything(converted: ConvertedCheckin) -> bool:
    return any(getattr(converted, name) is not None for name in ALL_CHECKIN_FIELDS)


def record_said(
    session: Session, said: str, provider: LLMProvider, decide: Decide | None = None
) -> DailyCheckIn | None:
    """The backstop for words the Guide only talked about: a check-in when they report the day
    and the converter finds a field, otherwise nothing."""
    said = said.strip()
    if not said:
        return None
    if decide is not None:
        try:
            answer, confidence = decide(f"The learner said:\n{said}", [DAILY_GATE])["daily"]
            if answer == "no" and confidence >= CONFIDENT:
                return None
        except Exception:
            logger.info("daily gate failed, asking the converter", exc_info=True)
    today = local_today()
    converted = CheckinConverter(provider).convert(said, today)
    if not found_anything(converted):
        return None
    return _fill_in(session, today, converted, said)


def run_said(engine: Engine, said: str, provider_factory: Callable[[], LLMProvider], decide: Decide | None) -> None:
    """Background-task entry point; best effort."""
    try:
        with Session(engine) as session:
            record_said(session, said, provider_factory(), decide)
    except Exception:
        logger.warning("check-in from the voice log failed", exc_info=True)


def said_later(add_task: Callable[..., None], engine: Engine) -> Callable[[str], None]:
    """A `log_said(said)` for a request: `record_said` after the response."""

    def log_said(said: str) -> None:
        decide = decisions.decide if decisions.available() else None
        add_task(run_said, engine, said, lambda: get_provider("checkin_converter"), decide)

    return log_said


def edit_checkin(session: Session, day: date, body: CheckInEdit) -> DailyCheckIn:
    """Sets the fields sent in `body` on `day`'s check-in (made if there is none): the life
    overview's way to fix or fill in a day. Raises FutureDate after today."""
    if day > local_today():
        raise FutureDate(day)
    record = session.exec(select(DailyCheckIn).where(DailyCheckIn.date == day)).first()
    if record is None:
        record = DailyCheckIn(date=day, source=CheckInSource.manual)
    for name in body.model_fields_set & set(ALL_CHECKIN_FIELDS):
        setattr(record, name, getattr(body, name))
    if record.exercise_minutes and record.exercised is None:
        record.exercised = True
    session.add(record)
    session.commit()
    session.refresh(record)
    return record


def todays_checkin(session: Session) -> DailyCheckIn | None:
    return session.exec(select(DailyCheckIn).where(DailyCheckIn.date == local_today())).first()
