"""学习计划接口。"""

import json
import logging

from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session, select

from app.agents.recommender import Recommender
from app.db import get_session
from app.llm import get_provider
from app.models import SkillNode, SkillStatus, StudyPlan
from app.schemas import PlanStepOut, StudyPlanOut
from app.services import bandit
from app.services.profile import build_profile

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/plan", tags=["plan"])


def _to_out(session: Session, plan: StudyPlan) -> StudyPlanOut:
    """把存下来的计划还原成前端要的形状。

    节点标题不存进 steps_json，每次读取时按 skill_id 现查——标题可能被改过，
    而计划里显示的必须是节点当下的样子。指向已被删除节点的步骤直接跳过。
    """
    steps_raw = json.loads(plan.steps_json)
    context = json.loads(plan.context_json)

    steps: list[PlanStepOut] = []
    for step in steps_raw:
        skill = session.get(SkillNode, step["skill_id"])
        if skill is None:
            continue
        steps.append(
            PlanStepOut(
                skill_id=skill.id,
                skill_title=skill.title,
                node_type=skill.node_type,
                rationale=step.get("rationale", ""),
                focus_hint=step.get("focus_hint", ""),
            )
        )

    return StudyPlanOut(
        id=plan.id,
        steps=steps,
        suggested_tier=context.get("suggested_tier", ""),
        context_bucket=context.get("context_bucket", ""),
        created_at=plan.created_at,
    )


@router.get("/current", response_model=StudyPlanOut | None)
def get_current_plan(session: Session = Depends(get_session)):
    """最近一份计划；从未生成过就返回 null（不是 404 —— 空状态是正常的）。"""
    plan = session.exec(select(StudyPlan).order_by(StudyPlan.created_at.desc())).first()
    return _to_out(session, plan) if plan else None


@router.post("/generate", response_model=StudyPlanOut)
def generate_plan(session: Session = Depends(get_session)):
    available = session.exec(select(SkillNode).where(SkillNode.status == SkillStatus.available)).all()
    if not available:
        raise HTTPException(400, "当前没有可挑战的节点，先生成技能树或通过已有节点解锁")

    bucket = bandit.context_bucket(session)
    tier = bandit.choose_tier(session, bucket)
    tiers = {s.id: bandit.difficulty_tier(session, s) for s in available}
    profile = build_profile(session)

    try:
        steps = Recommender(get_provider()).recommend(
            available,
            tiers,
            suggested_tier=tier,
            context_bucket=bucket,
            clusters=profile.clusters,
            health=profile.health,
            sanity=profile.sanity,
        )
    except Exception:
        logger.warning("plan generation failed", exc_info=True)
        # choose_tier 会创建 bandit 臂，即使规划失败也该落库，否则下次采样从头开始。
        session.commit()
        raise HTTPException(502, "学习计划生成失败，请稍后重试")

    plan = StudyPlan(
        steps_json=json.dumps(
            [{"skill_id": s.skill_id, "rationale": s.rationale, "focus_hint": s.focus_hint} for s in steps],
            ensure_ascii=False,
        ),
        context_json=json.dumps(
            {"suggested_tier": tier, "context_bucket": bucket}, ensure_ascii=False
        ),
    )
    session.add(plan)
    session.commit()
    session.refresh(plan)
    return _to_out(session, plan)
