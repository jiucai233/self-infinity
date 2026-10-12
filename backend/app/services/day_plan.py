"""What a day's plan may hold (contract #15): how much focus is left, what the time of day is
for, and which nodes are due for review.

- **Focus budget.** About four hours of focused work a day is the ceiling: deliberate practice
  runs to about four hours a day even among experts [Ericsson et al., 1993]. The condition
  scales it: `low` halves it, `unknown` (no check-in) keeps three quarters. What today's audits
  took already (first question to last answer) is spent.
- **Time of day.** Mornings are for what takes judgement (new nodes, challenges, branches),
  evenings for recall: reviewing what was learned, so that sleep consolidates it [Gais et al.,
  2006; Diekelmann & Born, 2010]. Late at night a short review at most. The shares are a
  default; the player's own day may differ (chronotype, [Schmidt et al., 2007]).
- **Review** is retrieval practice [Roediger & Karpicke, 2006], spaced out [Cepeda et al.,
  2006]: a node explained well is due again 1, 3, 7, 14 and then every 30 days after its passes;
  in the evening, what was passed earlier today is due before sleep.
"""

from dataclasses import dataclass
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from sqlmodel import Session, col, select

from app import utils
from app.config import settings
from app.models import AuditSession, AuditStatus, AuditTurn, DailyCheckIn, NodeType, SkillNode, SkillStatus
from app.services.courses import live_node_ids

FOCUS_CAP_MINUTES = 240
CONDITION_SHARE = {"normal": 1.0, "unknown": 0.75, "low": 0.5}

# Slots by local hour: morning 5-12, afternoon 12-18, evening 18-23, night 23-5.
# The share of the focus left that goes to judgement (learning, challenges); the rest is review.
THINKING_SHARE = {"morning": 0.8, "afternoon": 0.6, "evening": 0.25, "night": 0.0}
# On a low day less of it is judgement, and no challenge.
LOW_THINKING = 0.6

# Rough minutes per task, to fit the budget.
MINUTES = {"learn_leaf": 25, "learn_task": 15, "learn_branch": 30, "challenge": 35, "review": 10}

# Days after the n-th pass before a node is due again.
REVIEW_DAYS = (1, 3, 7, 14, 30)
# Passed this long before an evening: due again before sleep.
TONIGHT_AFTER = timedelta(hours=2)

# An audit counts at least this much focus, and at most this much (a tab left open).
MIN_AUDIT_MINUTES = 2
MAX_AUDIT_MINUTES = 60


def slot_of(now: datetime) -> str:
    hour = now.hour
    if 5 <= hour < 12:
        return "morning"
    if 12 <= hour < 18:
        return "afternoon"
    if 18 <= hour < 23:
        return "evening"
    return "night"


def focus_budget(flag: str) -> int:
    return round(FOCUS_CAP_MINUTES * CONDITION_SHARE.get(flag, CONDITION_SHARE["unknown"]))


def _zone() -> ZoneInfo:
    return ZoneInfo(settings.app_timezone)


def focus_spent(session: Session, now: datetime) -> int:
    """Minutes today's audits took: from their start to their last turn."""
    zone = _zone()
    today = now.astimezone(zone).date()
    start = datetime.combine(today, datetime.min.time(), zone)
    audits = session.exec(
        select(AuditSession).where(AuditSession.created_at >= start, AuditSession.created_at < start + timedelta(days=1))
    ).all()
    total = 0.0
    for audit in audits:
        last = session.exec(
            select(AuditTurn.created_at)
            .where(AuditTurn.session_id == audit.id)
            .order_by(col(AuditTurn.created_at).desc())
        ).first()
        if last is None:
            continue
        minutes = (last - audit.created_at).total_seconds() / 60
        total += min(MAX_AUDIT_MINUTES, max(MIN_AUDIT_MINUTES, minutes))
    return round(total)


@dataclass
class Review:
    node: SkillNode
    passes: int
    last: datetime  # the latest finished audit
    tonight: bool  # passed earlier today, due before sleep
    overdue: float  # days past due (0 for tonight)


def reviews_due(session: Session, now: datetime, slot: str) -> list[Review]:
    """Mastered nodes due for review, the most pressing first: tonight's, then the most overdue.
    Only nodes the player explained themselves (a passed audit), not ones a challenge cleared."""
    zone = _zone()
    today = now.astimezone(zone).date()
    live = live_node_ids(session)
    finished = session.exec(
        select(AuditSession)
        .where(col(AuditSession.status) != AuditStatus.active)
        .order_by(AuditSession.created_at)
    ).all()
    by_node: dict[int, list[AuditSession]] = {}
    for audit in finished:
        if audit.skill_id in live:
            by_node.setdefault(audit.skill_id, []).append(audit)
    due: list[Review] = []
    for node_id, audits in by_node.items():
        passed = [a for a in audits if a.status == AuditStatus.passed]
        node = session.get(SkillNode, node_id)
        if not passed or node is None or node.status != SkillStatus.mastered or node.linked_course_id is not None:
            continue
        last = audits[-1].created_at
        first_pass_today = passed[0].created_at.astimezone(zone).date() == today and len(passed) == 1
        if slot in ("evening", "night") and first_pass_today and now - last >= TONIGHT_AFTER:
            due.append(Review(node, len(passed), last, tonight=True, overdue=0))
            continue
        interval = REVIEW_DAYS[min(len(passed), len(REVIEW_DAYS)) - 1]
        age = (now - last).total_seconds() / 86400
        if age >= interval:
            due.append(Review(node, len(passed), last, tonight=False, overdue=age - interval))
    due.sort(key=lambda r: (not r.tonight, -r.overdue, r.node.id))
    return due


def learn_minutes(node: SkillNode, position: str) -> int:
    if node.unexpanded:
        return MINUTES["challenge"]
    if position != "leaf":
        return MINUTES["learn_branch"]
    return MINUTES["learn_task"] if node.node_type == NodeType.task else MINUTES["learn_leaf"]


def thinking_share(slot: str, flag: str) -> float:
    share = THINKING_SHARE[slot]
    return share * LOW_THINKING if flag == "low" else share


def challenges_allowed(slot: str, flag: str) -> bool:
    return flag != "low" and slot in ("morning", "afternoon")


def today_checkin(session: Session, now: datetime) -> DailyCheckIn | None:
    return session.exec(select(DailyCheckIn).where(DailyCheckIn.date == now.astimezone(_zone()).date())).first()


def now() -> datetime:
    return utils.local_now()
