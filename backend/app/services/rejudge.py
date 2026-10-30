"""Finished audits judged again under the Auditor's current rules (contract #50).

The rules change (app/agents/auditor.py JUDGE_VERSION); the audits already held keep the
verdict they were given under the old ones. Judging their transcripts again under the new rules
shows what the change does on real conversations, which a calibration set of made-up ones only
approximates. The second verdict is kept beside the first, never in its place: the user saw the
first one. One exception: an old fail kept no evidence for the replay, and when the new rules
fail it too, its gaps and their evidence are taken from the new verdict.

One judgement each, no votes and no Challenger: it is a measurement, not a verdict to act on.
The calls run side by side; the session is only touched before and after them.
"""

import contextvars
import json
import logging
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass

from sqlmodel import Session, col, select

from app.agents.auditor import JUDGE_VERSION, Auditor, AuditorTurnResult
from app.i18n import use_language
from app.llm.base import LLMProvider, Message
from app.models import AuditSession, AuditStatus, SkillNode, TurnRole
from app.services import audit_flow, audit_style
from app.services.tree import child_titles

logger = logging.getLogger(__name__)

# Audits judged again per request: each is one model call, all at once.
BATCH = 5


@dataclass
class _Job:
    audit_id: int
    language: str | None
    kwargs: dict


def stale(session: Session) -> list[AuditSession]:
    """Finished audits given under other rules and not yet judged again under these, oldest first."""
    rows = session.exec(
        select(AuditSession)
        .where(AuditSession.status != AuditStatus.active)
        .order_by(col(AuditSession.created_at), col(AuditSession.id))
    ).all()
    return [a for a in rows if a.judge_version != JUDGE_VERSION and a.rejudged_version != JUDGE_VERSION]


def _job(session: Session, audit: AuditSession) -> _Job | None:
    skill = session.get(SkillNode, audit.skill_id)
    turns = audit_flow.audit_turns(session, audit.id)
    history: list[Message] = [
        {
            "role": "user" if t.role == TurnRole.user else "assistant",
            "content": f"{t.feedback}\n\n{t.content}" if t.feedback else t.content,
        }
        for t in turns
    ]
    answers = sum(1 for m in history if m["role"] == "user")
    if skill is None or not answers or history[-1]["role"] != "user":
        return None
    examined = [{"title": p["title"], "note": p.get("note")} for p in audit.points]
    parts = audit_flow.test_out_parts(session, skill) if audit.test_out else child_titles(session, skill)
    return _Job(
        audit_id=audit.id,
        language=audit_flow.audit_language(session, skill, audit),
        kwargs={
            "skill_title": skill.title,
            "skill_description": skill.description,
            "history": history,
            "node_type": skill.node_type,
            # The transcript is over: this judgement is its verdict.
            "max_turns": answers,
            "position": audit.node_position,
            "child_titles": parts,
            "after_challenge": audit.challenged,
            "test_out": bool(audit.test_out),
            "points": examined or None,
            "closed": audit_flow.closed_points(audit.points, turns) if examined else None,
            "audience": audit.audience or audit_style.DEFAULT_STYLE[0],
            "depth": audit.depth if audit.depth is not None else audit_style.DEFAULT_STYLE[1],
        },
    )


def _judge(provider: LLMProvider, job: _Job) -> AuditorTurnResult | None:
    try:
        with use_language(job.language):
            result = Auditor(provider).next_turn(**job.kwargs)
    except Exception:
        logger.warning("judging audit %s again failed", job.audit_id, exc_info=True)
        return None
    return result if result.is_verdict else None


def run(session: Session, provider: LLMProvider, limit: int = BATCH) -> dict:
    """Judges up to `limit` stale audits again; how many were, how many came out the other way,
    and how many are left."""
    todo = stale(session)
    jobs = [j for j in (_job(session, a) for a in todo[:limit]) if j is not None]
    # An audit with nothing to judge (no answer) is marked, so it is not picked again.
    skipped = [a for a in todo[:limit] if a.id not in {j.audit_id for j in jobs}]
    results: list[AuditorTurnResult | None] = []
    if jobs:
        with ThreadPoolExecutor(len(jobs)) as pool:
            calls = [pool.submit(contextvars.copy_context().run, _judge, provider, job) for job in jobs]
            results = [c.result() for c in calls]
    judged = changed = 0
    for job, result in zip(jobs, results):
        if result is None:
            continue
        audit = session.get(AuditSession, job.audit_id)
        passed = bool(result.passed)
        audit.rejudged_version = JUDGE_VERSION
        audit.rejudged_passed = passed
        judged += 1
        changed += passed != (audit.status == AuditStatus.passed)
        if audit.status == AuditStatus.failed and not passed and not audit.evidence_json and result.evidence:
            audit.gaps_json = json.dumps(result.gaps or [], ensure_ascii=False)
            audit.evidence_json = json.dumps(result.evidence, ensure_ascii=False)
        session.add(audit)
    for audit in skipped:
        audit.rejudged_version = JUDGE_VERSION
        session.add(audit)
    session.commit()
    return {"judged": judged, "changed": changed, "left": len(stale(session)), "version": JUDGE_VERSION}


def summary(session: Session) -> dict:
    """The audits judged again under these rules, and how many the rules would decide otherwise."""
    rows = session.exec(select(AuditSession).where(AuditSession.rejudged_version == JUDGE_VERSION)).all()
    rows = [a for a in rows if a.rejudged_passed is not None]
    return {
        "version": JUDGE_VERSION,
        "judged": len(rows),
        "changed": sum(1 for a in rows if a.rejudged_passed != (a.status == AuditStatus.passed)),
        "left": len(stale(session)),
    }
