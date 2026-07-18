import json

from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session, select

from app.agents.auditor import Auditor
from app.agents.scribe import Scribe
from app.db import get_session
from app.llm import get_provider
from app.llm.base import Message
from app.models import (
    AuditSession,
    AuditStatus,
    AuditTurn,
    NodeType,
    Principle,
    SkillNode,
    SkillStatus,
    TurnRole,
)
from app.schemas import (
    AuditSessionOut,
    AuditTurnOut,
    PrincipleOut,
    ReflectionRequest,
    StartAuditResponse,
    SubmitTurnRequest,
    TurnResultResponse,
)

router = APIRouter(prefix="/api", tags=["audits"])

CONCEPT_OPENING_TEMPLATE = "假设我完全没听说过「{title}」，从零开始，讲给我听。"
TASK_OPENING_TEMPLATE = "「{title}」这一步，你打算具体怎么做？"


def _opening_question(skill: SkillNode) -> str:
    template = CONCEPT_OPENING_TEMPLATE if skill.node_type == NodeType.concept else TASK_OPENING_TEMPLATE
    return template.format(title=skill.title)


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
def start_audit(skill_id: int, session: Session = Depends(get_session)):
    skill = session.get(SkillNode, skill_id)
    if skill is None:
        raise HTTPException(404, "skill not found")
    if skill.status == SkillStatus.locked:
        raise HTTPException(400, "skill is locked")

    audit = AuditSession(skill_id=skill_id, status=AuditStatus.active)
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

    auditor = Auditor(get_provider())
    try:
        result = auditor.next_turn(skill.title, skill.description, history, node_type=skill.node_type)
    except Exception:
        session.commit()
        raise HTTPException(502, "审计官暂时无法响应，请稍后重试")

    if not result.is_verdict:
        session.add(AuditTurn(session_id=audit.id, role=TurnRole.auditor, content=result.question))
        session.commit()
        return TurnResultResponse(type="probe", question=result.question)

    audit.status = AuditStatus.passed if result.passed else AuditStatus.failed
    audit.score = result.score
    audit.gaps_json = json.dumps(result.gaps or [])
    audit.comment = result.comment
    session.add(audit)

    unlocked_ids: list[int] = []
    if result.passed:
        skill.status = SkillStatus.mastered
        skill.mastery_score = result.score
        session.add(skill)

        children = session.exec(
            select(SkillNode).where(SkillNode.parent_id == skill.id, SkillNode.status == SkillStatus.locked)
        ).all()
        for child in children:
            child.status = SkillStatus.available
            session.add(child)
            unlocked_ids.append(child.id)

    session.commit()

    return TurnResultResponse(
        type="verdict",
        passed=result.passed,
        score=result.score,
        gaps=result.gaps or [],
        comment=result.comment,
        unlocked_skill_ids=unlocked_ids,
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
        title, principle_body = scribe.distill(skill.title, gaps, body.reflection)
    except Exception:
        raise HTTPException(502, "原则蒸馏失败，请稍后重试")

    principle = Principle(title=title, body=principle_body, source_session_id=audit.id)
    session.add(principle)
    session.commit()
    session.refresh(principle)

    return principle
