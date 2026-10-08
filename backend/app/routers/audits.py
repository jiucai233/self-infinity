import json
import logging

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query
from sqlmodel import Session, col, select

from app.agents.recorder import Recorder
from app.db import get_session
from app.llm import get_provider
from app.models import AuditSession, AuditStatus, Principle, SkillNode, SkillStatus
from app.routers.principles import principle_out
from app.schemas import (
    AuditSessionOut,
    AuditSummaryOut,
    AuditTurnOut,
    PrincipleOut,
    ProbeResult,
    ReflectionRequest,
    StartAuditRequest,
    StartAuditResponse,
    SubmitTurnRequest,
    TurnResult,
    VerdictResult,
)
from app.services import audit_flow, linking
from app.services.audit_flow import AuditClosed, AuditorUnavailable, ProbeOutcome

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api", tags=["audits"])


def _session_out(session: Session, audit: AuditSession) -> AuditSessionOut:
    return AuditSessionOut(
        id=audit.id,
        skill_id=audit.skill_id,
        node_position=audit.node_position,
        status=audit.status,
        score=audit.score,
        gaps=json.loads(audit.gaps_json) if audit.gaps_json else [],
        comment=audit.comment,
        turns=[AuditTurnOut(role=t.role.value, content=t.content) for t in audit_flow.audit_turns(session, audit.id)],
        test_out=bool(audit.test_out),
    )


def audit_summary(audit: AuditSession, skill: SkillNode) -> AuditSummaryOut:
    return AuditSummaryOut(
        id=audit.id,
        skill_id=skill.id,
        skill_title=skill.title,
        status=audit.status,
        score=audit.score,
        created_at=audit.created_at,
        test_out=bool(audit.test_out),
    )


@router.get("/audits", response_model=list[AuditSummaryOut])
def list_audits(limit: int = Query(20, ge=1, le=100), session: Session = Depends(get_session)):
    """Audits of all courses, newest first."""
    rows = session.exec(
        select(AuditSession, SkillNode)
        .join(SkillNode, SkillNode.id == AuditSession.skill_id)
        .order_by(col(AuditSession.created_at).desc(), col(AuditSession.id).desc())
        .limit(limit)
    ).all()
    return [audit_summary(audit, skill) for audit, skill in rows]


@router.post("/skills/{skill_id}/audits", response_model=StartAuditResponse)
def start_audit(
    skill_id: int,
    body: StartAuditRequest = StartAuditRequest(),
    session: Session = Depends(get_session),
):
    skill = session.get(SkillNode, skill_id)
    if skill is None:
        raise HTTPException(404, "skill not found")
    if body.test_out:
        # A challenge skips what it covers, so it is open whether or not the node is.
        if skill.status == SkillStatus.mastered:
            raise HTTPException(400, "skill is already mastered")
        if not audit_flow.can_test_out(session, skill):
            raise HTTPException(400, "Only a branch or a whole course can be challenged.")
    else:
        # 已通过的节点可以再审；requires 没满足也可以审（requires 只影响推荐顺序）。
        if skill.status == SkillStatus.locked:
            raise HTTPException(400, "skill is locked")
        if skill.unexpanded:
            raise HTTPException(400, "Break this node down first, or challenge it as a whole.")

    audit, question = audit_flow.start_audit(session, skill, body.mode, test_out=body.test_out)
    return StartAuditResponse(session=_session_out(session, audit), opening_question=question)


@router.post("/audits/{audit_id}/turns", response_model=TurnResult)
def submit_turn(audit_id: int, body: SubmitTurnRequest, session: Session = Depends(get_session)):
    audit = session.get(AuditSession, audit_id)
    if audit is None:
        raise HTTPException(404, "audit session not found")
    if audit.status != AuditStatus.active:
        raise HTTPException(400, "audit session is already closed")
    skill = session.get(SkillNode, audit.skill_id)

    try:
        outcome = audit_flow.submit_turn(
            session,
            audit,
            skill,
            body.content,
            auditor_provider=get_provider("auditor"),
            challenger_provider=get_provider("challenger"),
        )
    except AuditorUnavailable:
        raise HTTPException(502, "The auditor is temporarily unavailable. Please try again.")
    except AuditClosed:
        raise HTTPException(400, "audit session is already closed")

    if isinstance(outcome, ProbeOutcome):
        return ProbeResult(question=outcome.question)
    return VerdictResult(
        passed=outcome.passed,
        score=outcome.score,
        gaps=outcome.gaps,
        comment=outcome.comment,
        unlocked_skill_ids=outcome.unlocked_skill_ids,
        reward_amount=outcome.reward_amount,
        reward_multiplier=outcome.reward_multiplier,
    )


@router.post("/audits/{audit_id}/reflection", response_model=PrincipleOut)
def submit_reflection(
    audit_id: int,
    body: ReflectionRequest,
    background: BackgroundTasks,
    session: Session = Depends(get_session),
):
    audit = session.get(AuditSession, audit_id)
    if audit is None:
        raise HTTPException(404, "audit session not found")
    if audit.status != AuditStatus.failed:
        raise HTTPException(400, "reflection is only accepted for a failed audit")
    if session.exec(select(Principle.id).where(Principle.source_session_id == audit.id)).first() is not None:
        raise HTTPException(400, "reflection already submitted for this audit")

    skill = session.get(SkillNode, audit.skill_id)
    gaps = json.loads(audit.gaps_json) if audit.gaps_json else []

    try:
        lesson = Recorder(get_provider("recorder")).distill(skill.title, gaps, body.reflection)
    except Exception:
        logger.warning("recorder failed", exc_info=True)
        raise HTTPException(502, "Principle extraction failed. Please try again.")

    principle = Principle(
        title=lesson.title,
        body=lesson.body,
        misconception=lesson.misconception,
        source_session_id=audit.id,
    )
    session.add(principle)
    session.commit()
    session.refresh(principle)

    # Linker 在响应发出之后才跑：用户不用等一次纯粹为了以后服务的 LLM 调用。后台任务
    # 自己开 session（请求的那个届时已经关了），所以把引擎和 provider 交给它。
    background.add_task(linking.run_linker, session.get_bind(), lambda: get_provider("linker"), principle.id)

    return principle_out(principle, skill)
