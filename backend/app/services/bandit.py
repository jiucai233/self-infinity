"""V2.1 contextual bandit (whitepaper §4.4): picks which difficulty tier to
steer the user toward next, so the app leans them toward "reachable
difficulty" instead of always surfacing whatever's biggest/first.

The whitepaper names LinUCB or Thompson Sampling and is explicit that the
choice should be "statistically honest" for a single-user, small-sample,
cold-start setting — a full LinUCB linear regression over continuous
context features would need far more data than one person's usage
generates to fit meaningfully. This implements Thompson Sampling over a
*discretized* context instead: the three raw context features (recent pass
rate, abandon rate, average session duration) get collapsed into one
"readiness" bucket (low/mid/high) rather than binned separately and
cross-produced (3x3x3 = 27 arms would starve every cell for a single user's
data volume). Combined with 3 difficulty tiers that's 9 Beta-Bernoulli
arms total — small enough that even a few dozen resolved audits give each
arm some signal.

Note on "abandon rate": there's no explicit abandon action in the UI (no
"give up" button), so it's approximated by AuditSession rows stuck in
`active` status for longer than STALE_ACTIVE_HOURS with no resolution —
a real proxy, not a fabricated number, but worth stating plainly since
it's inferred rather than a direct signal.
"""

import random
from datetime import timedelta

from sqlmodel import Session, select

from app.models import AuditSession, AuditStatus, AuditTurn, BanditArm, SkillNode, as_utc, utcnow
from app.services.incentive import node_difficulty_score

TIERS = ("easy", "medium", "hard")
CONTEXT_BUCKETS = ("low", "mid", "high")

RECENT_WINDOW = 10  # how many recent resolved/active sessions feed the context features
STALE_ACTIVE_HOURS = 2


def difficulty_tier(session: Session, skill: SkillNode, depth: int | None = None) -> str:
    score = node_difficulty_score(session, skill, depth)
    if score <= 1.5:
        return "easy"
    if score <= 3.0:
        return "medium"
    return "hard"


def _recent_sessions(session: Session, exclude_id: int | None = None) -> list[AuditSession]:
    rows = session.exec(select(AuditSession).order_by(AuditSession.created_at.desc())).all()
    if exclude_id is not None:
        rows = [r for r in rows if r.id != exclude_id]
    return rows[:RECENT_WINDOW]


def _pass_rate(resolved: list[AuditSession]) -> float:
    if not resolved:
        return 0.5  # no data yet: neither optimistic nor pessimistic
    passed = sum(1 for r in resolved if r.status == AuditStatus.passed)
    return passed / len(resolved)


def _abandon_rate(recent: list[AuditSession]) -> float:
    if not recent:
        return 0.0
    stale_cutoff = utcnow() - timedelta(hours=STALE_ACTIVE_HOURS)
    stale = sum(1 for s in recent if s.status == AuditStatus.active and as_utc(s.created_at) < stale_cutoff)
    return stale / len(recent)


def _avg_duration_seconds(session: Session, resolved: list[AuditSession]) -> float:
    if not resolved:
        return 0.0
    durations: list[float] = []
    for s in resolved:
        last_turn = session.exec(
            select(AuditTurn).where(AuditTurn.session_id == s.id).order_by(AuditTurn.created_at.desc())
        ).first()
        if last_turn is not None:
            durations.append((last_turn.created_at - s.created_at).total_seconds())
    return sum(durations) / len(durations) if durations else 0.0


def context_bucket(session: Session, exclude_id: int | None = None) -> str:
    """Composite "readiness" bucket for the user's current state.

    Higher pass rate, lower abandon rate, and shorter average sessions (a
    proxy for explaining cleanly on the first pass rather than circling)
    all push toward "high" — meaning the user can probably handle harder
    material right now.
    """
    recent = _recent_sessions(session, exclude_id)
    resolved = [r for r in recent if r.status != AuditStatus.active]

    pass_rate = _pass_rate(resolved)
    abandon_rate = _abandon_rate(recent)
    avg_duration = _avg_duration_seconds(session, resolved)
    # Duration has no reliable population scale from one user's data, so it's
    # folded in as a coarse 0/0.5/1 score rather than a normalized continuous
    # value.
    duration_score = 1.0 if avg_duration <= 120 else (0.5 if avg_duration <= 300 else 0.0)

    readiness = pass_rate * 0.5 + (1 - abandon_rate) * 0.3 + duration_score * 0.2
    if readiness >= 0.66:
        return "high"
    if readiness >= 0.4:
        return "mid"
    return "low"


def _get_or_create_arm(session: Session, bucket: str, tier: str) -> BanditArm:
    arm = session.exec(
        select(BanditArm).where(BanditArm.context_bucket == bucket, BanditArm.tier == tier)
    ).first()
    if arm is None:
        arm = BanditArm(context_bucket=bucket, tier=tier)
        session.add(arm)
        session.flush()
    return arm


def choose_tier(session: Session, bucket: str) -> str:
    """Thompson Sampling: sample each tier's Beta posterior for this
    context bucket, recommend whichever sample is highest. Naturally
    explores under-tried arms (wide posterior -> high-variance samples)
    and exploits well-established ones (narrow posterior around the
    observed success rate) without a separate exploration schedule."""
    best_tier = TIERS[0]
    best_sample = -1.0
    for tier in TIERS:
        arm = _get_or_create_arm(session, bucket, tier)
        sample = random.betavariate(arm.alpha, arm.beta)
        if sample > best_sample:
            best_sample = sample
            best_tier = tier
    return best_tier


def update_arm(session: Session, bucket: str, tier: str, reward: bool) -> None:
    arm = _get_or_create_arm(session, bucket, tier)
    if reward:
        arm.alpha += 1
    else:
        arm.beta += 1
    session.add(arm)
