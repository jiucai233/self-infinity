"""Recording a daily check-in (contract #12) and reading today's (#21).

Shared by POST /api/checkins and the chat `checkin` intent, so both go through the same
Check-in Converter flow. One row per KST calendar day: a second check-in on the same day
replaces the first. A field that is not given stays null, it is never copied from an earlier day.
"""

from collections.abc import Callable
from datetime import date

from sqlmodel import Session, select

from app.agents.checkin_converter import CheckinConverter, ConvertedCheckin
from app.llm.base import LLMProvider
from app.models import CheckInSource, DailyCheckIn, utcnow
from app.schemas import ALL_CHECKIN_FIELDS, CHECKIN_FIELDS, CheckInEdit, CheckInRequest, CheckInResponse, DailyCheckInOut
from app.utils import local_today


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
        values = {f: getattr(converted, f) for f in ALL_CHECKIN_FIELDS}
        transcript, source = body.transcript, CheckInSource.voice
    else:
        values = {f: getattr(body, f) for f in ALL_CHECKIN_FIELDS}
        transcript, source = None, CheckInSource.manual

    record = session.exec(select(DailyCheckIn).where(DailyCheckIn.date == today)).first()
    if record is None:
        record = DailyCheckIn(date=today)
    for name, value in values.items():
        setattr(record, name, value)
    record.transcript = transcript
    record.source = source
    record.created_at = utcnow()
    session.add(record)
    session.commit()
    session.refresh(record)

    return CheckInResponse(
        checkin=DailyCheckInOut.model_validate(record),
        missing_fields=[f for f in CHECKIN_FIELDS if getattr(record, f) is None],
    )


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
