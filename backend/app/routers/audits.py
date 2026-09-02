import json
import logging

from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session, select

from app.agents.auditor import Auditor
from app.agents.challenger import ChallengeResult, Challenger
from app.agents.retrieval import (
    collect_recent_misconceptions,
    find_recurring_misconception,
    find_relevant_principles,
)
from app.agents.scribe import Scribe
from app.db import get_session
from app.llm import get_provider
from app.llm.base import Message
from app.models import (
    AuditSession,
    AuditStatus,
    AuditTurn,
    FocusSession,
    NodeType,
    Principle,
    RewardEvent,
    SkillNode,
    SkillStatus,
    TurnRole,
    utcnow,
)
from app.services.linking import link_principle
from app.services.tree import NodePosition, child_titles, node_position
from app.config import settings
from app.schemas import (
    AuditSessionOut,
    AuditTurnOut,
    PrincipleOut,
    ReflectionRequest,
    StartAuditRequest,
    StartAuditResponse,
    SubmitTurnRequest,
    TurnResultResponse,
)
from app.services import bandit
from app.services.focus import compute_focus_score
from app.services.incentive import compute_reward
from app.services.vitality import apply_audit_result

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api", tags=["audits"])

# 开场问题也按位置分。一个分类节点上来就问"从零讲给我听"，等于把它当成具体知识点，
# 后面再怎么追问都拉不回来——第一个问题定了整场审计的框架。
LEAF_OPENING_TEMPLATE = "假设我完全没听说过「{title}」，从零开始，讲给我听。"
BRANCH_OPENING_TEMPLATE = "「{title}」下面放着{children}。为什么这几样被归在一起？它们之间怎么选？"
ROOT_OPENING_TEMPLATE = "什么样的问题该用「{title}」这套方法解决，什么样的不该？说说你判断的依据。"
TASK_OPENING_TEMPLATE = "「{title}」这一步，你打算具体怎么做？"


def _opening_question(skill: SkillNode, position: NodePosition, children: list[str]) -> str:
    if skill.node_type != NodeType.concept:
        return TASK_OPENING_TEMPLATE.format(title=skill.title)
    if position == NodePosition.root:
        return ROOT_OPENING_TEMPLATE.format(title=skill.title)
    if position == NodePosition.branch:
        return BRANCH_OPENING_TEMPLATE.format(title=skill.title, children="、".join(children))
    return LEAF_OPENING_TEMPLATE.format(title=skill.title)


def _resolve_max_turns(node_type: NodeType, mode: str) -> int:
    base = settings.audit_max_turns if node_type == NodeType.concept else settings.task_max_turns
    return base * 2 if mode == "night" else base


def _maybe_challenge(session: Session, skill: SkillNode, history: list[Message]) -> ChallengeResult | None:
    """对一个 pass 裁决跑一次复核，返回有效挑战；维持原判或复核失败都返回 None。

    Challenger 的作用是收紧裁决，它自己出问题不该让整场审计失败——所以任何异常
    都吞掉当作"维持原判"，而不是像 Auditor 那样冒 502。
    """
    try:
        misconceptions = collect_recent_misconceptions(session, settings.challenger_misconception_limit)
        result = Challenger(get_provider()).review(
            skill.title, skill.description, history, misconceptions
        )
    except Exception:
        logger.warning("challenger failed, upholding the auditor verdict", exc_info=True)
        return None
    return result if result.overturned else None


def _session_out(session: Session, audit: AuditSession) -> AuditSessionOut:
    turns = session.exec(
        select(AuditTurn).where(AuditTurn.session_id == audit.id).order_by(AuditTurn.created_at)
    ).all()
    return AuditSessionOut(
        id=audit.id,
        skill_id=audit.skill_id,
        status=audit.status,
        score=audit.score,
        gaps=json.loads(audit.gaps_json) if audit.gaps_json else [],
        comment=audit.comment,
        turns=[AuditTurnOut(role=t.role, content=t.content) for t in turns],
    )


@router.post("/skills/{skill_id}/audits", response_model=StartAuditResponse)
def start_audit(skill_id: int, body: StartAuditRequest = StartAuditRequest(), session: Session = Depends(get_session)):
    skill = session.get(SkillNode, skill_id)
    if skill is None:
        raise HTTPException(404, "skill not found")
    if skill.status == SkillStatus.locked:
        raise HTTPException(400, "skill is locked")

    max_turns = _resolve_max_turns(skill.node_type, body.mode)
    audit = AuditSession(skill_id=skill_id, status=AuditStatus.active, max_turns=max_turns)
    session.add(audit)
    session.flush()

    opening = _opening_question(skill, node_position(session, skill), child_titles(session, skill))
    turn = AuditTurn(session_id=audit.id, role=TurnRole.auditor, content=opening)
    session.add(turn)
    session.commit()
    session.refresh(audit)

    return StartAuditResponse(session=_session_out(session, audit), opening_question=opening)


@router.post("/audits/{audit_id}/turns", response_model=TurnResultResponse)
def submit_turn(audit_id: int, body: SubmitTurnRequest, session: Session = Depends(get_session)):
    audit = session.get(AuditSession, audit_id)
    if audit is None:
        raise HTTPException(404, "audit session not found")
    if audit.status != AuditStatus.active:
        raise HTTPException(400, "audit session is already closed")

    skill = session.get(SkillNode, audit.skill_id)

    user_turn = AuditTurn(session_id=audit.id, role=TurnRole.user, content=body.content)
    session.add(user_turn)
    session.flush()

    prior_turns = session.exec(
        select(AuditTurn).where(AuditTurn.session_id == audit.id).order_by(AuditTurn.created_at)
    ).all()
    history: list[Message] = [
        {"role": "user" if t.role == TurnRole.user else "assistant", "content": t.content}
        for t in prior_turns
    ]

    relevant_principles = find_relevant_principles(session, skill)
    principle_texts = [f"{p.title}：{p.body}" for p in relevant_principles]

    auditor = Auditor(get_provider())
    try:
        result = auditor.next_turn(
            skill.title,
            skill.description,
            history,
            node_type=skill.node_type,
            relevant_principles=principle_texts,
            max_turns=audit.max_turns,
            position=node_position(session, skill),
            child_titles=child_titles(session, skill),
        )
    except Exception:
        session.commit()
        raise HTTPException(502, "审计官暂时无法响应，请稍后重试")

    if not result.is_verdict:
        session.add(AuditTurn(session_id=audit.id, role=TurnRole.auditor, content=result.question))
        session.commit()
        return TurnResultResponse(type="probe", question=result.question)

    # 只复核 pass 裁决，且每场审计至多一次（challenged 是那道收敛保证）。fail 不需要
    # 复核——Challenger 的目标函数是推翻通过，对一个已经不通过的裁决无事可做。挑战
    # 不直接翻转裁决，而是变成最后一个追问：用户有机会回应，再由 Auditor 出最终裁决，
    # 届时 challenged 已为真，不会再次触发。详见 app/agents/challenger.py。
    if result.passed and settings.challenger_enabled and not audit.challenged:
        challenge = _maybe_challenge(session, skill, history)
        if challenge is not None:
            audit.challenged = True
            session.add(audit)
            session.add(AuditTurn(session_id=audit.id, role=TurnRole.auditor, content=challenge.question))
            session.commit()
            logger.info("challenger overturned a pass verdict: %s", challenge.reason)
            return TurnResultResponse(type="probe", question=challenge.question)

    # Context is computed excluding this session (its own outcome can't
    # leak into the state used to judge which tier was worth recommending
    # before we knew the result) — see app/services/bandit.py.
    bucket = bandit.context_bucket(session, exclude_id=audit.id)
    tier = bandit.difficulty_tier(session, skill)

    audit.status = AuditStatus.passed if result.passed else AuditStatus.failed
    audit.score = result.score
    audit.gaps_json = json.dumps(result.gaps or [])
    audit.comment = result.comment
    session.add(audit)
    apply_audit_result(session, result.passed)
    bandit.update_arm(session, bucket, tier, reward=result.passed)

    unlocked_ids: list[int] = []
    reward_amount: int | None = None
    reward_multiplier: float | None = None
    if result.passed:
        skill.status = SkillStatus.mastered
        skill.mastery_score = result.score
        session.add(skill)
        session.flush()

        children = session.exec(
            select(SkillNode).where(SkillNode.parent_id == skill.id, SkillNode.status == SkillStatus.locked)
        ).all()
        for child in children:
            child.status = SkillStatus.available
            session.add(child)
            unlocked_ids.append(child.id)

        reward_amount, reward_multiplier = compute_reward(session, skill)
        session.add(RewardEvent(session_id=audit.id, amount=reward_amount, multiplier=reward_multiplier))

    focus_score = compute_focus_score([t.created_at for t in prior_turns], result.passed)
    session.add(
        FocusSession(
            started_at=audit.created_at,
            ended_at=utcnow(),
            focus_score=focus_score,
            source="audit_engagement",
        )
    )

    session.commit()

    return TurnResultResponse(
        type="verdict",
        passed=result.passed,
        score=result.score,
        gaps=result.gaps or [],
        comment=result.comment,
        unlocked_skill_ids=unlocked_ids,
        reward_amount=reward_amount,
        reward_multiplier=reward_multiplier,
    )


@router.post("/audits/{audit_id}/reflection", response_model=PrincipleOut)
def submit_reflection(audit_id: int, body: ReflectionRequest, session: Session = Depends(get_session)):
    audit = session.get(AuditSession, audit_id)
    if audit is None:
        raise HTTPException(404, "audit session not found")
    if audit.status != AuditStatus.failed:
        raise HTTPException(400, "reflection is only accepted for a failed audit")

    skill = session.get(SkillNode, audit.skill_id)
    gaps = json.loads(audit.gaps_json) if audit.gaps_json else []

    scribe = Scribe(get_provider())
    try:
        title, principle_body, misconception = scribe.distill(skill.title, gaps, body.reflection)
    except Exception:
        raise HTTPException(502, "原则蒸馏失败，请稍后重试")

    recurring_of = find_recurring_misconception(session, misconception)

    principle = Principle(
        title=title, body=principle_body, misconception=misconception, source_session_id=audit.id
    )
    session.add(principle)
    session.commit()
    session.refresh(principle)

    link_principle(session, get_provider(), principle, exclude_skill_id=audit.skill_id)

    return PrincipleOut(
        id=principle.id,
        title=principle.title,
        body=principle.body,
        misconception=principle.misconception,
        source_session_id=principle.source_session_id,
        recurring_of_id=recurring_of.id if recurring_of else None,
        recurring_of_title=recurring_of.title if recurring_of else None,
    )
