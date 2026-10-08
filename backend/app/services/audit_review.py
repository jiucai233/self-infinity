"""The developer panel (contract #34): every finished audit with its transcript, the reviews the
developers gave the verdicts, and the metrics they add up to. No LLM.

A review says whether the Auditor judged right: `right`, `too_strict` (it failed an audit that
should have passed) or `too_lenient` (it passed one that should have failed), plus whether it
gave the answer away. From the reviews the human verdict of each reviewed audit follows, and the
Auditor's verdicts are compared with them: the share it got right, and Cohen's kappa, which
discounts the agreement two raters would reach by chance.
"""

import json

from sqlmodel import Session, col, select

from app.models import AuditSession, AuditStatus, AuditTurn, SkillNode, TurnRole
from app.schemas import DevAuditOut, DevMetricsOut, DevTurnOut


class ReviewError(Exception):
    pass


def _rate(part: float, whole: int) -> float | None:
    return round(part / whole, 4) if whole else None


def kappa(pairs: list[tuple[bool, bool]]) -> float | None:
    """Cohen's kappa over (auditor passed, human passed) pairs; None when it is undefined."""
    n = len(pairs)
    if not n:
        return None
    observed = sum(a == h for a, h in pairs) / n
    auditor = sum(a for a, _ in pairs) / n
    human = sum(h for _, h in pairs) / n
    chance = auditor * human + (1 - auditor) * (1 - human)
    return None if chance == 1 else round((observed - chance) / (1 - chance), 4)


def human_passed(audit: AuditSession) -> bool:
    passed = audit.status == AuditStatus.passed
    return passed if audit.review == "right" else not passed


def metrics(audits: list[AuditSession], answers: dict[int, int]) -> DevMetricsOut:
    finished = [a for a in audits if a.status != AuditStatus.active]
    passed = [a for a in finished if a.status == AuditStatus.passed]
    failed = [a for a in finished if a.status == AuditStatus.failed]
    reviewed = [a for a in finished if a.review]
    return DevMetricsOut(
        finished=len(finished),
        pass_rate=_rate(len(passed), len(finished)),
        avg_score=_rate(sum(a.score or 0 for a in finished), len(finished)),
        avg_gaps_when_failed=_rate(sum(len(json.loads(a.gaps_json or "[]")) for a in failed), len(failed)),
        avg_answers=_rate(sum(answers.get(a.id, 0) for a in finished), len(finished)),
        challenged_rate=_rate(sum(a.challenged for a in finished), len(finished)),
        reviewed=len(reviewed),
        agreement=_rate(sum(a.review == "right" for a in reviewed), len(reviewed)),
        kappa=kappa([(a.status == AuditStatus.passed, human_passed(a)) for a in reviewed]),
        too_strict=sum(a.review == "too_strict" for a in reviewed),
        too_lenient=sum(a.review == "too_lenient" for a in reviewed),
        leaked=sum(bool(a.review_leaked) for a in reviewed),
    )


def _out(audit: AuditSession, title: str, turns: list[AuditTurn]) -> DevAuditOut:
    return DevAuditOut(
        id=audit.id,
        skill_id=audit.skill_id,
        skill_title=title,
        status=audit.status.value,
        score=audit.score,
        gaps=json.loads(audit.gaps_json or "[]"),
        comment=audit.comment,
        turns=[DevTurnOut(role=t.role.value, content=t.content) for t in turns],
        review=audit.review,
        leaked=bool(audit.review_leaked),
        created_at=audit.created_at,
    )


def _turns(session: Session, ids: list[int]) -> dict[int, list[AuditTurn]]:
    by_audit: dict[int, list[AuditTurn]] = {i: [] for i in ids}
    for turn in session.exec(
        select(AuditTurn).where(col(AuditTurn.session_id).in_(ids)).order_by(AuditTurn.id)
    ).all():
        by_audit[turn.session_id].append(turn)
    return by_audit


def dev_audits(session: Session, limit: int) -> tuple[DevMetricsOut, list[DevAuditOut]]:
    """The metrics over every finished audit, and the newest [limit] of them."""
    audits = session.exec(
        select(AuditSession).where(AuditSession.status != AuditStatus.active).order_by(col(AuditSession.id).desc())
    ).all()
    answers = _count_answers(session)
    shown = audits[:limit]
    titles = dict(
        session.exec(select(SkillNode.id, SkillNode.title).where(col(SkillNode.id).in_({a.skill_id for a in shown}))).all()
    )
    turns = _turns(session, [a.id for a in shown])
    return metrics(audits, answers), [_out(a, titles.get(a.skill_id, ""), turns[a.id]) for a in shown]


def _count_answers(session: Session) -> dict[int, int]:
    counts: dict[int, int] = {}
    for session_id in session.exec(select(AuditTurn.session_id).where(AuditTurn.role == TurnRole.user)).all():
        counts[session_id] = counts.get(session_id, 0) + 1
    return counts


def review(session: Session, audit_id: int, value: str | None, leaked: bool) -> DevAuditOut:
    audit = session.get(AuditSession, audit_id)
    if audit is None:
        raise LookupError
    if audit.status == AuditStatus.active:
        raise ReviewError("audit is not finished")
    if value == "too_strict" and audit.status != AuditStatus.failed:
        raise ReviewError("too_strict is for a failed audit")
    if value == "too_lenient" and audit.status != AuditStatus.passed:
        raise ReviewError("too_lenient is for a passed audit")
    audit.review = value
    audit.review_leaked = leaked if value else None
    session.add(audit)
    session.commit()
    session.refresh(audit)
    skill = session.get(SkillNode, audit.skill_id)
    return _out(audit, skill.title if skill else "", _turns(session, [audit.id])[audit.id])
