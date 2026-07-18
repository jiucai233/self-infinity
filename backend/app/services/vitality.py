"""Vitality System (体力系统) V2 — see docs/WHITEPAPER.md §4.5.

Health is derived from a 7-day rolling average of daily check-in
self-ratings (spending / activity / eating, each 1-3). Health does not
grant rewards directly; it only shapes Sanity's ceiling and regen rate.
Sanity is the resourced expression of audit behavior: it rises on audit
pass, decays on audit fail, capped at sanity_cap.

Constants chosen (documented per the task spec, tune here if needed):

    HEALTH_WINDOW_DAYS = 7      # rolling window size for health
    SANITY_CAP_BASE   = 40.0    # sanity_cap at health=0
    SANITY_CAP_K      = 0.6     # sanity_cap = 40 + 0.6*health -> range [40, 100]
    SANITY_REGEN_RATE0 = 8.0    # sanity gain per audit pass at health=0
    SANITY_REGEN_K     = 0.5    # gain per audit pass at health=100 = 8*(1+0.5)=12
    SANITY_FAIL_DECAY  = 5.0    # fixed sanity loss per audit fail
    SANITY_DEFAULT     = 50.0   # baseline sanity for a freshly created VitalityState

Worked example: 7 check-ins all rated "2" (average) -> per-day score
(2-1)/2*100 = 50 -> health = 50.
    sanity_cap  = 40 + 0.6*50            = 70
    sanity_regen (per pass) = 8*(1+0.5*50/100) = 8*1.25 = 10
A pass takes sanity from e.g. 50 -> min(70, 50+10) = 60.
A fail takes sanity from 60 -> max(0, 60-5) = 55.
"""

from __future__ import annotations

from sqlmodel import Session, select

from app.models import DailyCheckIn, VitalityState, utcnow

HEALTH_WINDOW_DAYS = 7

SANITY_CAP_BASE = 40.0
SANITY_CAP_K = 0.6

SANITY_REGEN_RATE0 = 8.0
SANITY_REGEN_K = 0.5

SANITY_FAIL_DECAY = 5.0

SANITY_DEFAULT = 50.0


def compute_health(session: Session) -> float:
    """7-day rolling average of daily check-in ratings, scaled to 0-100.

    Each check-in day's 3 ratings (1-3 each) are averaged into a single
    per-day score, then averaged across the most recent
    HEALTH_WINDOW_DAYS check-ins available (fewer is fine — we just
    average whatever exists). The 1-3 average is then linearly mapped
    to 0-100 via (avg - 1) / 2 * 100, so a rating of 1 -> 0, 2 -> 50,
    3 -> 100. With no check-ins at all, health defaults to 50 (neutral
    starting point, matching SANITY_DEFAULT).
    """
    recent = session.exec(
        select(DailyCheckIn).order_by(DailyCheckIn.date.desc()).limit(HEALTH_WINDOW_DAYS)
    ).all()
    if not recent:
        return 50.0

    day_scores = [
        (c.spending_rating + c.activity_rating + c.eating_rating) / 3.0 for c in recent
    ]
    avg_rating = sum(day_scores) / len(day_scores)
    health = (avg_rating - 1) / 2 * 100
    return max(0.0, min(100.0, health))


def compute_sanity_cap(health: float) -> float:
    """sanity_cap = base + k * health, base=40, k=0.6 -> range [40, 100]."""
    return SANITY_CAP_BASE + SANITY_CAP_K * health


def compute_sanity_regen(health: float) -> float:
    """sanity_regen = rate0 * (1 + k' * health/100), rate0=8, k'=0.5 -> [8, 12]."""
    return SANITY_REGEN_RATE0 * (1 + SANITY_REGEN_K * health / 100)


def get_or_create_vitality_state(session: Session) -> VitalityState:
    """Fetch the single VitalityState row, creating a default one if absent.

    Defaults: health=50 (neutral), sanity=SANITY_DEFAULT, sanity_cap
    computed from health=50 so a fresh state is internally consistent.
    """
    state = session.exec(select(VitalityState)).first()
    if state is not None:
        return state

    health = 50.0
    state = VitalityState(
        health=health,
        sanity=SANITY_DEFAULT,
        sanity_cap=compute_sanity_cap(health),
    )
    session.add(state)
    session.commit()
    session.refresh(state)
    return state


def recompute_health_and_cap(session: Session) -> VitalityState:
    """Recompute health/sanity_cap from the check-in rolling window and persist.

    Called after a new check-in is recorded. Sanity itself is untouched
    here — it only moves via audit pass/fail (see apply_audit_result).
    """
    state = get_or_create_vitality_state(session)
    health = compute_health(session)
    state.health = health
    state.sanity_cap = compute_sanity_cap(health)
    # Sanity may exceed a newly-lowered cap; keep it consistent.
    state.sanity = min(state.sanity, state.sanity_cap)
    state.updated_at = utcnow()
    session.add(state)
    session.commit()
    session.refresh(state)
    return state


def apply_audit_result(session: Session, passed: bool) -> VitalityState:
    """Update sanity in response to an audit verdict.

    PASS: sanity = min(sanity_cap, sanity + sanity_regen(health))
    FAIL: sanity = max(0, sanity - SANITY_FAIL_DECAY)

    "长期空档" (long-inactivity decay) is intentionally not implemented —
    a simplified version was judged out of scope; only the core
    pass/fail update loop is handled here, per the whitepaper's own
    note that the tracking side must stay lightweight.
    """
    state = get_or_create_vitality_state(session)
    if passed:
        regen = compute_sanity_regen(state.health)
        state.sanity = min(state.sanity_cap, state.sanity + regen)
    else:
        state.sanity = max(0.0, state.sanity - SANITY_FAIL_DECAY)
    state.updated_at = utcnow()
    session.add(state)
    session.commit()
    session.refresh(state)
    return state
