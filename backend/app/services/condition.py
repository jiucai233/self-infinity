"""Condition flag and audit pacing, from the most recent daily check-ins (plan 8.4 / 8.5).

The flag looks at the last 3 check-ins: `low` if the average sleep is under 6 hours or the
average stress is 4 or more, `unknown` when there is no check-in at all, otherwise `normal`.
Averages ignore the fields a check-in left empty (a missing value is never guessed).

Pacing is the only thing the flag changes in an audit: `light` keeps the Auditor's questions
short. It never changes the turn limit or the pass standard. The thresholds are to be tuned.
"""

import logging
from dataclasses import dataclass

from sqlmodel import Session, col, select

from app.models import DailyCheckIn

logger = logging.getLogger(__name__)

CHECKIN_WINDOW = 3
LOW_SLEEP_HOURS = 6
HIGH_STRESS = 4


@dataclass
class Condition:
    days: int  # check-ins used, 0-3
    avg_sleep_hours: float | None
    avg_stress: float | None
    flag: str  # "low" | "normal" | "unknown"


def _mean(values: list[int | None]) -> float | None:
    present = [v for v in values if v is not None]
    return sum(present) / len(present) if present else None


def current_condition(session: Session) -> Condition:
    rows = session.exec(
        select(DailyCheckIn).order_by(col(DailyCheckIn.date).desc()).limit(CHECKIN_WINDOW)
    ).all()
    if not rows:
        return Condition(days=0, avg_sleep_hours=None, avg_stress=None, flag="unknown")

    avg_sleep = _mean([r.sleep_hours for r in rows])
    avg_stress = _mean([r.stress for r in rows])
    low = (avg_sleep is not None and avg_sleep < LOW_SLEEP_HOURS) or (
        avg_stress is not None and avg_stress >= HIGH_STRESS
    )
    return Condition(days=len(rows), avg_sleep_hours=avg_sleep, avg_stress=avg_stress, flag="low" if low else "normal")


def audit_pacing(session: Session) -> str:
    """`light` when the condition flag is low, otherwise `normal`."""
    return "light" if current_condition(session).flag == "low" else "normal"
