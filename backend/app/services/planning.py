"""Study plans (contract #15, #16): the Recommender's order over the available nodes.

Shared by POST /api/plan/generate and the chat `plan` intent.
"""

import json
import logging
from collections.abc import Callable

from sqlmodel import Session, col, select

from app.agents.recommender import Candidate, Recommender
from app.llm.base import LLMProvider
from app.models import EdgeKind, SkillEdge, SkillNode, SkillStatus, StudyPlan
from app.schemas import PlanStepOut, StudyPlanOut
from app.services import bandit
from app.services.condition import current_condition
from app.services.profile import cluster_misconceptions
from app.services.tree import depth_map, node_position

logger = logging.getLogger(__name__)


class NoAvailableNode(Exception):
    """There is nothing to plan: no node is available."""


class PlanFailed(Exception):
    """The Recommender could not produce a plan."""


def plan_out(plan: StudyPlan) -> StudyPlanOut:
    context = json.loads(plan.context_json)
    return StudyPlanOut(
        id=plan.id,
        suggested_tier=context["suggested_tier"],
        context_bucket=context["context_bucket"],
        created_at=plan.created_at,
        steps=[PlanStepOut(**step) for step in json.loads(plan.steps_json)],
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
        result.append(
            Candidate(
                skill_id=node.id,
                title=node.title,
                position=node_position(session, node).value,
                tier=bandit.difficulty_tier(session, node, depths.get(node.id, 0)),
                unmet_requires=unmet,
            )
        )
    return result


def current_plan(session: Session) -> StudyPlan | None:
    return session.exec(select(StudyPlan).order_by(col(StudyPlan.created_at).desc(), col(StudyPlan.id).desc())).first()


def generate_plan(session: Session, provider_for: Callable[[str], LLMProvider]) -> StudyPlanOut:
    available = list(
        session.exec(select(SkillNode).where(SkillNode.status == SkillStatus.available).order_by(SkillNode.id)).all()
    )
    if not available:
        raise NoAvailableNode

    bucket = bandit.context_bucket(session)
    tier = bandit.choose_tier(session, bucket)
    session.commit()  # choose_tier may have created bandit arms
    candidates = _candidates(session, available)
    clusters = cluster_misconceptions(session)
    flag = current_condition(session).flag

    try:
        steps = Recommender(provider_for("recommender")).recommend(candidates, tier, clusters, flag)
    except Exception as exc:
        logger.warning("recommender failed", exc_info=True)
        raise PlanFailed from exc

    by_id = {n.id: n for n in available}
    plan = StudyPlan(
        steps_json=json.dumps(
            [
                {
                    "skill_id": s.skill_id,
                    "course_id": by_id[s.skill_id].course_id,
                    "skill_title": by_id[s.skill_id].title,
                    "node_type": by_id[s.skill_id].node_type.value,
                    "rationale": s.rationale,
                    "focus_hint": s.focus_hint,
                }
                for s in steps
            ],
            ensure_ascii=False,
        ),
        context_json=json.dumps(
            {"suggested_tier": tier, "context_bucket": bucket, "condition_flag": flag}, ensure_ascii=False
        ),
    )
    session.add(plan)
    session.commit()
    session.refresh(plan)
    return plan_out(plan)
