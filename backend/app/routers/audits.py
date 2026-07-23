import json

from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session, select

from app.agents.auditor import Auditor
from app.agents.retrieval import find_recurring_misconception, find_relevant_principles
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

router = APIRouter(prefix="/api", tags=["audits"])

CONCEPT_OPENING_TEMPLATE = "假设我完全没听说过「{title}」，从零开始，讲给我听。"
TASK_OPENING_TEMPLATE = "「{title}」这一步，你打算具体怎么做？"


def _opening_question(skill: SkillNode) -> str:
    template = CONCEPT_OPENING_TEMPLATE if skill.node_type == NodeType.concept else TASK_OPENING_TEMPLATE
    return template.format(title=skill.title)


def _resolve_max_turns(node_type: NodeType, mode: str) -> int:
    base = settings.audit_max_turns if node_type == NodeType.concept else settings.task_max_turns
    return base * 2 if mode == "night" else base


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

    opening = _opening_question(skill)
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
        )
    except Exception:
        session.commit()
        raise HTTPException(502, "审计官暂时无法响应，请稍后重试")

    if not result.is_verdict:
        session.add(AuditTurn(session_id=audit.id, role=TurnRole.auditor, content=result.question))
        session.commit()
        return TurnResultResponse(type="probe", question=result.question)

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
