"""Study plans (contract #15, #16): today's quests for this time of day, fitted to the focus
left (app/services/day_plan.py), the Recommender ordering what takes judgement.

Shared by POST /api/plan/generate and the chat `plan` intent.
"""

import json
import logging
from collections.abc import Callable

from sqlmodel import Session, col, select

from app.agents.recommender import MAX_STEPS, Candidate, Recommender
from app.i18n import t
from app.llm.base import LLMProvider
from app.models import DailyCheckIn, EdgeKind, SkillEdge, SkillNode, SkillStatus, StudyPlan
from app.schemas import PlanStepOut, StudyPlanOut
from app.services import bandit, day_plan, learner, life
from app.services.condition import current_condition
from app.services.courses import live_nodes
from app.services.profile import cluster_misconceptions
from app.services.tree import depth_map, node_position

logger = logging.getLogger(__name__)


class NoAvailableNode(Exception):
    """There is nothing to plan: no node is available."""


class PlanFailed(Exception):
    """The Recommender could not produce a plan."""


def plan_out(plan: StudyPlan) -> StudyPlanOut:
    context = json.loads(plan.context_json)
    now = day_plan.now()
    # A plan is for one time of day of one day; after that it is stale and made again.
    stale = context.get("date") != now.date().isoformat() or context.get("slot") != day_plan.slot_of(now)
    return StudyPlanOut(
        id=plan.id,
        suggested_tier=context["suggested_tier"],
        context_bucket=context["context_bucket"],
        created_at=plan.created_at,
        steps=[PlanStepOut(**step) for step in json.loads(plan.steps_json)],
        slot=context.get("slot"),
        condition_flag=context.get("condition_flag"),
        focus_budget=context.get("focus_budget"),
        focus_spent=context.get("focus_spent"),
        focus_left=context.get("focus_left"),
        summary=context.get("summary", ""),
        stale=stale,
    )


def _candidates(session: Session, nodes: list[SkillNode]) -> list[Candidate]:
    all_nodes = {n.id: n for n in session.exec(select(SkillNode)).all()}
    requires = session.exec(select(SkillEdge).where(SkillEdge.kind == EdgeKind.requires)).all()
    depths = depth_map(session)
    result = []
    for node in nodes:
        unmet = [
            all_nodes[e.from_id].title
            for e in requires
            if e.to_id == node.id and all_nodes[e.from_id].status != SkillStatus.mastered
        ]
        position = node_position(session, node).value
        tier = bandit.difficulty_tier(session, node, depths.get(node.id, 0))
        result.append(
            Candidate(
                skill_id=node.id,
                title=node.title,
                position=position,
                tier=tier,
                chance=round(learner.node_chance(session, node, tier) * 100),
                unmet_requires=unmet,
                kind="challenge" if node.unexpanded else "learn",
                minutes=day_plan.learn_minutes(node, position),
            )
        )
    return result


def _thinking(candidates: list[Candidate], slot: str, flag: str) -> list[Candidate]:
    """What the time of day and the condition allow: no challenge in the evening or on a low
    day, and then only leaves when there are any."""
    if not day_plan.challenges_allowed(slot, flag):
        candidates = [c for c in candidates if c.kind != "challenge"]
        leaves = [c for c in candidates if c.position == "leaf"]
        candidates = leaves or candidates
    return candidates


def _duration(minutes: int) -> str:
    h, m = divmod(max(0, minutes), 60)
    if h and m:
        return t("duration_hm", h=h, m=m)
    return t("duration_h", h=h) if h else t("duration_m", m=m)


def _pattern_line(session: Session, today: DailyCheckIn | None) -> str | None:
    """The player's own numbers for a day like today, when they have them: e.g. a short night,
    and how their audits went on their short nights before."""
    if today is None:
        return None
    worse_today = {
        "sleep": today.sleep_hours is not None and today.sleep_hours < life.SHORT_SLEEP_HOURS,
        "stress": today.stress is not None and today.stress >= 4,
        "exercise": today.exercised is False and not today.exercise_minutes,
    }
    checkins = list(session.exec(select(DailyCheckIn)).all())
    for pattern in life.patterns(checkins, life.audits_by_day(session)):
        better, worse = pattern.better.pass_rate, pattern.worse.pass_rate
        if worse_today.get(pattern.kind) and better is not None and worse is not None and worse < better:
            return t(
                f"plan_pattern_{pattern.kind}",
                worse=round(worse * 100),
                better=round(better * 100),
                days=pattern.better.days + pattern.worse.days,
            )
    return None


def _summary(slot: str, flag: str, spent: int, left: int, rest: bool, pattern: str | None) -> str:
    lines = [t(f"plan_{slot}")]
    if flag in ("low", "unknown"):
        lines.append(t(f"plan_{flag}"))
    if pattern:
        lines.append(pattern)
    lines.append(t("plan_rest", spent=_duration(spent)) if rest else t("plan_focus_left", left=_duration(left), spent=_duration(spent)))
    return " ".join(lines)


def current_plan(session: Session) -> StudyPlan | None:
    return session.exec(select(StudyPlan).order_by(col(StudyPlan.created_at).desc(), col(StudyPlan.id).desc())).first()


def generate_plan(session: Session, provider_for: Callable[[str], LLMProvider]) -> StudyPlanOut:
    """Today's quests for this time of day (app/services/day_plan.py): the focus left, split
    between judgement (new nodes, challenges; the Recommender orders them) and review (due nodes,
    the most pressing first), fitted to the minutes each takes. Raises NoAvailableNode when there
    is nothing to learn or review, PlanFailed when the Recommender fails."""
    now = day_plan.now()
    slot = day_plan.slot_of(now)
    flag = current_condition(session).flag
    budget = day_plan.focus_budget(flag)
    spent = day_plan.focus_spent(session, now)
    left = max(0, budget - spent)

    # A node that is another course is learned in that course, not audited here.
    available = list(
        session.exec(
            live_nodes()
            .where(SkillNode.status == SkillStatus.available, col(SkillNode.linked_course_id).is_(None))
            .order_by(SkillNode.id)
        ).all()
    )
    reviews = day_plan.reviews_due(session, now, slot)
    if not available and not reviews:
        raise NoAvailableNode

    bucket = bandit.context_bucket(session)
    tier = bandit.choose_tier(session, bucket)
    session.commit()  # choose_tier may have created bandit arms

    rest = left < day_plan.MINUTES["review"]
    share = day_plan.thinking_share(slot, flag)
    steps: list[dict] = []
    if not rest:
        # Review first by its share (at most its share of the five steps, one late at night).
        review_cap = 1 if slot == "night" else max(1, round(MAX_STEPS * (1 - share)))
        review_budget = left * (1 - share)
        picked = _fit_reviews(reviews, review_budget, review_cap)
        # What review did not use goes to judgement, and the other way round.
        think_budget = left - len(picked) * day_plan.MINUTES["review"] if slot != "night" else 0
        thinking = _thinking(_candidates(session, available), slot, flag) if think_budget > 0 else []
        chosen: list[dict] = []
        if thinking:
            clusters = cluster_misconceptions(session)
            try:
                ordered = Recommender(provider_for("recommender")).recommend(thinking, tier, clusters, flag, slot)
            except Exception as exc:
                logger.warning("recommender failed", exc_info=True)
                raise PlanFailed from exc
            chosen = _fit_thinking(ordered, {c.skill_id: c for c in thinking}, think_budget, MAX_STEPS - len(picked))
        if not chosen and slot != "night":
            picked = _fit_reviews(reviews, left, MAX_STEPS)
        by_id = {n.id: n for n in available}
        steps = [
            {
                "skill_id": c.skill_id,
                "course_id": by_id[c.skill_id].course_id,
                "skill_title": by_id[c.skill_id].title,
                "node_type": by_id[c.skill_id].node_type.value,
                "rationale": rationale,
                "focus_hint": hint,
                "kind": c.kind,
                "minutes": c.minutes,
            }
            for c, rationale, hint in chosen
        ] + [
            {
                "skill_id": r.node.id,
                "course_id": r.node.course_id,
                "skill_title": r.node.title,
                "node_type": r.node.node_type.value,
                "rationale": t("review_tonight") if r.tonight else t("review_due", days=max(1, round((now - r.last).total_seconds() / 86400))),
                "focus_hint": t("review_hint"),
                "kind": "review",
                "minutes": day_plan.MINUTES["review"],
            }
            for r in picked
        ]

    summary = _summary(slot, flag, spent, left, rest, _pattern_line(session, day_plan.today_checkin(session, now)))
    plan = StudyPlan(
        steps_json=json.dumps(steps, ensure_ascii=False),
        context_json=json.dumps(
            {
                "suggested_tier": tier,
                "context_bucket": bucket,
                "condition_flag": flag,
                "date": now.date().isoformat(),
                "slot": slot,
                "focus_budget": budget,
                "focus_spent": spent,
                "focus_left": left,
                "summary": summary,
            },
            ensure_ascii=False,
        ),
    )
    session.add(plan)
    session.commit()
    session.refresh(plan)
    return plan_out(plan)


def _fit_reviews(reviews: list[day_plan.Review], budget: float, cap: int) -> list[day_plan.Review]:
    minutes = day_plan.MINUTES["review"]
    return reviews[: max(0, min(cap, int(budget // minutes)))]


def _fit_thinking(ordered, candidates: dict[int, Candidate], budget: float, cap: int) -> list:
    """The Recommender's order, kept while it fits the budget (the first one always, if it is not
    much over)."""
    chosen, used = [], 0
    for step in ordered:
        candidate = candidates.get(step.skill_id)
        if candidate is None or len(chosen) >= cap:
            continue
        fits = used + candidate.minutes <= budget or (not chosen and candidate.minutes <= budget * 1.5)
        if fits:
            chosen.append((candidate, step.rationale, step.focus_hint))
            used += candidate.minutes
    return chosen
