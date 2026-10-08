"""The life overview (contract #39): the player's own record of how they live, next to how they
learn. No LLM: everything here is counted from DailyCheckIn and AuditSession.

- `days`: every calendar day of the window (APP_TIMEZONE), check-in fields and audits.
- `summary`: averages over the window, and the first and last weight in it.
- `patterns`: the player's own days compared in two groups (slept 7 h or more vs under 6 h,
  exercised vs not, stress 1-2 vs 4-5): audits passed and focus in each. Counted over the whole
  history, shown once both groups have PATTERN_MIN_DAYS days. They are the player's own numbers,
  not causes: one person's days are few and confounded (proposal R-09), and a population result
  need not hold for one person anyway [Fisher et al., 2018].

The Life Coach (app/agents/life_coach.py) gets `coach_facts`: these numbers rounded and
summarised, never the daily rows.
"""

import json
from collections.abc import Callable
from dataclasses import dataclass
from datetime import date, timedelta
from zoneinfo import ZoneInfo

from sqlmodel import Session, col, select

from app.config import settings
from app.models import AuditSession, AuditStatus, DailyCheckIn, Goal, LifeAdvice, Profile, SkillNode, SkillStatus
from app.schemas import (
    LifeAdviceItemOut,
    LifeAdviceOut,
    LifeDayOut,
    LifeGroupOut,
    LifeOut,
    LifePatternOut,
    LifeSummaryOut,
)
from app.services.courses import live_nodes
from app.utils import local_today

PATTERN_MIN_DAYS = 5
GOOD_SLEEP_HOURS = 7
SHORT_SLEEP_HOURS = 6


def _mean(values: list[float | int | None]) -> float | None:
    present = [v for v in values if v is not None]
    return round(sum(present) / len(present), 1) if present else None


def _audits_by_day(session: Session) -> dict[date, tuple[int, int]]:
    """Finished audits per local day: (finished, passed)."""
    zone = ZoneInfo(settings.app_timezone)
    counts: dict[date, tuple[int, int]] = {}
    for audit in session.exec(select(AuditSession).where(col(AuditSession.status) != AuditStatus.active)).all():
        day = audit.created_at.astimezone(zone).date()
        finished, passed = counts.get(day, (0, 0))
        counts[day] = (finished + 1, passed + (audit.status == AuditStatus.passed))
    return counts


def _exercised(c: DailyCheckIn) -> bool | None:
    if c.exercise_minutes:
        return True
    return c.exercised


def _group(days: list[DailyCheckIn], audits: dict[date, tuple[int, int]]) -> LifeGroupOut:
    finished = sum(audits.get(c.date, (0, 0))[0] for c in days)
    passed = sum(audits.get(c.date, (0, 0))[1] for c in days)
    return LifeGroupOut(
        days=len(days),
        audits=finished,
        pass_rate=round(passed / finished, 2) if finished else None,
        avg_focus=_mean([c.focus for c in days]),
    )


SPLITS: dict[str, tuple[Callable[[DailyCheckIn], bool], Callable[[DailyCheckIn], bool]]] = {
    "sleep": (
        lambda c: c.sleep_hours is not None and c.sleep_hours >= GOOD_SLEEP_HOURS,
        lambda c: c.sleep_hours is not None and c.sleep_hours < SHORT_SLEEP_HOURS,
    ),
    "exercise": (lambda c: _exercised(c) is True, lambda c: _exercised(c) is False),
    "stress": (
        lambda c: c.stress is not None and c.stress <= 2,
        lambda c: c.stress is not None and c.stress >= 4,
    ),
}


def patterns(checkins: list[DailyCheckIn], audits: dict[date, tuple[int, int]]) -> list[LifePatternOut]:
    found = []
    for kind, (is_better, is_worse) in SPLITS.items():
        better = [c for c in checkins if is_better(c)]
        worse = [c for c in checkins if is_worse(c)]
        if len(better) >= PATTERN_MIN_DAYS and len(worse) >= PATTERN_MIN_DAYS:
            found.append(LifePatternOut(kind=kind, better=_group(better, audits), worse=_group(worse, audits)))
    return found


def _summary(window: int, logged: list[DailyCheckIn], days: list[LifeDayOut]) -> LifeSummaryOut:
    weights = [c.weight_kg for c in logged if c.weight_kg is not None]
    return LifeSummaryOut(
        days=window,
        days_logged=len(logged),
        avg_sleep_hours=_mean([c.sleep_hours for c in logged]),
        avg_sleep_quality=_mean([c.sleep_quality for c in logged]),
        exercise_days=sum(1 for c in logged if _exercised(c) is True),
        avg_exercise_minutes=_mean([c.exercise_minutes for c in logged if c.exercise_minutes]),
        avg_focus=_mean([c.focus for c in logged]),
        avg_stress=_mean([c.stress for c in logged]),
        weight_first=weights[0] if weights else None,
        weight_last=weights[-1] if weights else None,
        audits=sum(d.audits for d in days),
        passed=sum(d.passed for d in days),
    )


def latest_advice(session: Session) -> LifeAdviceOut | None:
    row = session.exec(select(LifeAdvice).order_by(col(LifeAdvice.generated_at).desc(), col(LifeAdvice.id).desc())).first()
    if row is None:
        return None
    return LifeAdviceOut(
        items=[LifeAdviceItemOut(**item) for item in json.loads(row.advice_json)],
        generated_at=row.generated_at,
    )


def overview(session: Session, window: int = 30) -> LifeOut:
    today = local_today()
    first = today - timedelta(days=window - 1)
    checkins = list(session.exec(select(DailyCheckIn).order_by(DailyCheckIn.date)).all())
    by_day = {c.date: c for c in checkins}
    audits = _audits_by_day(session)

    days: list[LifeDayOut] = []
    for offset in range(window):
        day = first + timedelta(days=offset)
        c = by_day.get(day)
        finished, passed = audits.get(day, (0, 0))
        fields = {} if c is None else {
            "sleep_hours": c.sleep_hours,
            "sleep_quality": c.sleep_quality,
            "exercised": _exercised(c),
            "exercise_minutes": c.exercise_minutes,
            "weight_kg": c.weight_kg,
            "diet_note": c.diet_note,
            "focus": c.focus,
            "stress": c.stress,
        }
        days.append(LifeDayOut(date=day, checked_in=c is not None, audits=finished, passed=passed, **fields))

    logged = [c for c in checkins if first <= c.date <= today]
    return LifeOut(
        summary=_summary(window, logged, days),
        days=days,
        patterns=patterns(checkins, audits),
        pattern_min_days=PATTERN_MIN_DAYS,
        advice=latest_advice(session),
    )


# ---------------------------------------------------------------- what the Life Coach sees


@dataclass
class CoachFacts:
    """Coarse numbers only: averages, counts and changes, never a daily row or a meal."""

    facts: dict


def coach_facts(session: Session, window: int = 14) -> CoachFacts:
    life = overview(session, window)
    s = life.summary
    weight_change = (
        round(s.weight_last - s.weight_first, 1)
        if s.weight_first is not None and s.weight_last is not None and s.days_logged > 1
        else None
    )
    profile = session.get(Profile, 1) or Profile()
    mastered = session.exec(live_nodes().where(SkillNode.status == SkillStatus.mastered)).all()
    return CoachFacts(
        facts={
            "window_days": window,
            "days_logged": s.days_logged,
            "averages": {
                "sleep_hours": s.avg_sleep_hours,
                "sleep_quality_1_5": s.avg_sleep_quality,
                "focus_1_5": s.avg_focus,
                "stress_1_5": s.avg_stress,
                "exercise_minutes_on_active_days": s.avg_exercise_minutes,
            },
            "exercise_days": s.exercise_days,
            "weight_change_kg": weight_change,
            "audits": {"finished": s.audits, "passed": s.passed},
            "patterns": [p.model_dump() for p in life.patterns],
            "learning": {"nodes_mastered_total": len(mastered)},
            "player": {
                "identity": profile.identity,
                "win_condition": profile.vision,
                "stakes": profile.anti_vision,
                "rules": json.loads(profile.rules_json or "[]"),
                "main_quests": [g.title for g in session.exec(select(Goal).order_by(Goal.id)).all()],
            },
        }
    )


def save_advice(session: Session, items: list[LifeAdviceItemOut], facts: CoachFacts) -> LifeAdviceOut:
    row = LifeAdvice(
        advice_json=json.dumps([i.model_dump() for i in items], ensure_ascii=False),
        facts_json=json.dumps(facts.facts, ensure_ascii=False),
    )
    session.add(row)
    session.commit()
    session.refresh(row)
    return LifeAdviceOut(items=items, generated_at=row.generated_at)
