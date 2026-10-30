"""审计流程的编排（Orchestrator，纯代码）：plan 6.6 的时序，一步不多一步不少。

提交一个回答时：保存回答 → Memory Retriever → Auditor →（pass 且没复核过：Challenger）→
保存 → 终判通过则解锁。路由层只管 404/400 这类 HTTP 语义，这里不碰 HTTP。

几条不能丢的规矩：

- 用户的回答先落库再调 Auditor。Auditor 挂了用户也不用重写一遍（路由返回 502）。重发时
  那条还没等到回复的回答被替换，而不是在它旁边再存一条（否则重复的回答会白占轮数上限）。
- 结算先原子地把会话从 active 改掉（`_claim`）：两个并发请求只有一个能结算，另一个得到
  AuditClosed（路由回 400），奖励和 bandit 不会记两次。
- Challenger 出任何问题都按维持原判处理——它只能收紧裁决，不能制造新的失败模式。
- 终判通过：节点 mastered 并写入 mastery_score，按学习顺序开下一个节点；记录奖励。失败：节点
  状态不动。
- 整块挑战（test_out）：对一个分支或整门课，从它下面抽几个部分来问；通过则它和它下面所有
  没通过的节点都算 mastered（tested_out 标记它们不是自己审过的）。锁着的也能挑战。
- 不用重来：一个节点上没结束的审计（RESUME_HOURS 小时内）再进来就接着来，原来的对话原样
  还在；要从头来得明说（restart）。带知识点的叶子只考还没过的知识点，裁决后把每个知识点的
  对错（和错在哪）写回节点（app/services/points.py），下一场从没过的那些开始。
"""

import contextvars
import json
import logging
from concurrent.futures import ThreadPoolExecutor
from collections import Counter
from dataclasses import dataclass, field
from datetime import timedelta
from typing import Sequence

from sqlalchemy import update
from sqlmodel import Session, col, select

from app.agents.auditor import JUDGE_VERSION, Auditor, AuditorTurnResult
from app.agents.challenger import Challenger
from app.agents.memory_retriever import recent_misconceptions, retrieve_lessons
from app.config import settings
from app.llm import second_auditor_provider
from app.llm.base import LLMProvider, Message
from app.models import (
    AuditSession,
    AuditStatus,
    AuditTurn,
    NodePosition,
    NodeType,
    Principle,
    PrincipleCheck,
    RewardEvent,
    SkillNode,
    SkillStatus,
    TurnRole,
    utcnow,
)
from app.i18n import join_list, language_of, quote, t
from app.services import audit_style, bandit, learner, points
from app.services.condition import audit_pacing
from app.services.incentive import compute_reward
from app.services.course_edit import sync_links
from app.services.tree import child_titles, contains_children, descendant_ids, node_position, open_next

logger = logging.getLogger(__name__)

# 开场问题按节点位置分（plan 17.2）。第一个问题定了整场审计的框架：一个分类节点上来
# 就问"从头讲给我听"，等于把它当成具体知识点，后面再怎么追问都拉不回来。
# The texts are in app/i18n.py (opening_leaf / _branch / _root / _task), in three languages.


class AuditorUnavailable(Exception):
    """The Auditor call failed (provider error); the user's answer is already saved."""


class AuditClosed(Exception):
    """Another request finalized this audit first."""


@dataclass
class ProbeOutcome:
    question: str
    feedback: str | None = None
    point: str | None = None


@dataclass
class VerdictOutcome:
    passed: bool
    score: int
    gaps: list[str]
    comment: str
    feedback: str | None = None
    points: list[dict] = field(default_factory=list)
    # One per gap: the user's own words it rests on and what holds instead.
    evidence: list[dict] = field(default_factory=list)
    # Past lessons this audit touched: `{"principle_id", "title", "held"}`.
    lessons: list[dict] = field(default_factory=list)
    unlocked_skill_ids: list[int] = field(default_factory=list)
    reward_amount: int | None = None
    reward_multiplier: float | None = None


TurnOutcome = ProbeOutcome | VerdictOutcome


# How many parts under a challenged node the Auditor is shown to sample from.
TEST_OUT_PARTS = 12

# An unfinished audit is picked up again for this long; after that a new one starts.
RESUME_HOURS = 24

# An audit with knowledge points gets two questions a point, within these bounds.
POINT_TURNS = 2
MIN_POINT_TURNS = 4
MAX_POINT_TURNS = 10


def can_test_out(session: Session, skill: SkillNode) -> bool:
    """A branch, a course's root, or a category not broken down yet: anything with parts."""
    return bool(skill.unexpanded) or node_position(session, skill) != NodePosition.leaf


def test_out_parts(session: Session, skill: SkillNode) -> list[str]:
    """Titles of the smallest units under `skill` (leaves, and categories not broken down yet),
    nearest first; empty for a category not broken down (its description names its parts)."""
    nodes = {n.id: n for n in session.exec(select(SkillNode).where(SkillNode.course_id == skill.course_id)).all()}
    parts = []
    for node_id in descendant_ids(session, skill.id):
        node = nodes.get(node_id)
        if node is not None and (node.unexpanded or not contains_children(session, node_id)):
            parts.append(node.title)
    return parts[:TEST_OUT_PARTS]


def audit_language(session: Session, skill: SkillNode, audit: AuditSession | None = None, answer: str = "") -> str | None:
    """The language an audit is held in, whatever the interface is set to: the one the user
    answers in ([answer] with their earlier answers of [audit]); before any answer, the node's
    own when that is not English (a Chinese course under an English interface is asked in
    Chinese). None: the request's language.

    Decided here, not left to the Auditor: told only to "write in theirs", it drifted back to
    English for a turn or two in the middle of a Chinese audit."""
    if audit is not None:
        said = [turn.content for turn in audit_turns(session, audit.id) if turn.role == TurnRole.user]
        spoken = language_of(" ".join([*said, answer]))
        if spoken is not None:
            return spoken
    written = language_of(" ".join([skill.title, skill.description or "", *(p["title"] for p in skill.points)]))
    return written if written in ("zh", "ko") else None


def opening_question(
    skill: SkillNode,
    position: NodePosition,
    children: list[str],
    test_out: bool = False,
    examined: list[str] | None = None,
    again: bool = False,
    audience: str | None = None,
) -> str:
    """An audit opens with the student asking to be taught, never with a question about one
    point: the user teaches, and what she asks afterwards comes out of what they said. `examined`: the
    knowledge points this audit is on (a leaf that has them); `again`: some of the node's
    points held before, so only the ones still open are to be explained. `audience`: who she is
    this time; a child or a colleague says so before asking (the default student says nothing)."""
    question = _opening(skill, position, children, test_out, examined, again)
    intro = t(f"audience_{audience}") if audience in ("child", "expert") else ""
    return f"{intro} {question}" if intro else question


def _opening(
    skill: SkillNode,
    position: NodePosition,
    children: list[str],
    test_out: bool,
    examined: list[str] | None,
    again: bool,
) -> str:
    if examined and again and not test_out:
        if len(examined) == 1:
            return t("opening_point_again", point=quote(examined[0]))
        return t("opening_points_again", points=join_list(examined))
    if test_out:
        if children:
            return t("opening_test_out", title=quote(skill.title), part=quote(children[0]))
        return t("opening_test_out_open", title=quote(skill.title))
    if skill.node_type == NodeType.task:
        return t("opening_task", title=quote(skill.title))
    if position == NodePosition.root:
        return t("opening_root", title=quote(skill.title))
    if position == NodePosition.branch:
        return t("opening_branch", title=quote(skill.title), children=join_list(children))
    return t("opening_leaf", title=quote(skill.title))


def closed_points(examined: list[dict], turns: list[AuditTurn]) -> list[str]:
    """The points of this audit that have had their questions (`POINT_TURNS` each): she asks no
    more about them, so one point cannot take the turns of the others, and a point that was
    explained is not dug into further."""
    asked = Counter(t.point for t in turns if t.role == TurnRole.auditor and t.point)
    return [p["title"] for p in examined if asked[p["title"]] >= POINT_TURNS]


def max_turns_for(node_type: NodeType, mode: str, examined: int = 0) -> int:
    """`examined`: how many knowledge points the audit asks about (0: an audit without points)."""
    base = settings.audit_max_turns if node_type == NodeType.concept else settings.task_max_turns
    if examined:
        base = max(MIN_POINT_TURNS, min(MAX_POINT_TURNS, POINT_TURNS * examined))
    return base * 2 if mode == "night" else base


def audit_turns(session: Session, audit_id: int) -> list[AuditTurn]:
    return list(
        session.exec(
            select(AuditTurn)
            .where(AuditTurn.session_id == audit_id)
            .order_by(col(AuditTurn.created_at), col(AuditTurn.id))
        ).all()
    )


def unfinished_audit(session: Session, skill: SkillNode, test_out: bool = False) -> AuditSession | None:
    """The audit of this node to go on with: its newest one, if it is still open and recent."""
    latest = session.exec(
        select(AuditSession)
        .where(AuditSession.skill_id == skill.id)
        .order_by(col(AuditSession.created_at).desc(), col(AuditSession.id).desc())
        .limit(1)
    ).first()
    if latest is None or latest.status != AuditStatus.active or bool(latest.test_out) != test_out:
        return None
    if latest.created_at < utcnow() - timedelta(hours=RESUME_HOURS):
        return None
    return latest


def start_audit(
    session: Session, skill: SkillNode, mode: str, test_out: bool = False, restart: bool = False
) -> tuple[AuditSession, str, bool]:
    """The audit, its first question, and whether it is an unfinished one picked up again
    (never with `restart`)."""
    if not restart:
        unfinished = unfinished_audit(session, skill, test_out)
        if unfinished is not None:
            first = next((t for t in audit_turns(session, unfinished.id) if t.role == TurnRole.auditor), None)
            if first is not None:
                return unfinished, first.content, True

    # The style is chosen on the learner model, so it must hold every audit before then.
    learner.catch_up(session)
    position = node_position(session, skill)
    examined = points.to_examine(skill) if not test_out and points.has_points(session, skill) else []
    # A challenge keeps its own standard (every part asked must hold); a style is for the
    # ordinary audit of one node.
    style, style_context = None, None
    if settings.audit_styles and not test_out:
        style_context = audit_style.context(session, skill)
        style = audit_style.choose(session, style_context)
    audit = AuditSession(
        skill_id=skill.id,
        node_position=position,
        status=AuditStatus.active,
        # A challenge samples several parts: it gets a concept's turns even over a task.
        max_turns=max_turns_for(NodeType.concept if test_out else skill.node_type, mode, len(examined)),
        test_out=True if test_out else None,
        points_json=points.dump(examined) if examined else None,
        audience=style.audience if style else None,
        depth=style.depth if style else None,
        style_context_json=json.dumps(style_context) if style_context else None,
    )
    session.add(audit)
    session.flush()

    parts = test_out_parts(session, skill) if test_out else child_titles(session, skill)
    question = opening_question(
        skill,
        position,
        parts,
        test_out,
        examined=[p["title"] for p in examined],
        again=len(examined) < len(skill.points),
        audience=audit.audience,
    )
    session.add(AuditTurn(session_id=audit.id, role=TurnRole.auditor, content=question))
    session.commit()
    session.refresh(audit)
    return audit, question, False


def submit_turn(
    session: Session,
    audit: AuditSession,
    skill: SkillNode,
    content: str,
    *,
    auditor_provider: LLMProvider,
    challenger_provider: LLMProvider,
) -> TurnOutcome:
    _save_answer(session, audit, content)

    # Her turns go back to her whole: what she already explained, then what she asked.
    turns = audit_turns(session, audit.id)
    history: list[Message] = [
        {
            "role": "user" if t.role == TurnRole.user else "assistant",
            "content": f"{t.feedback}\n\n{t.content}" if t.feedback else t.content,
        }
        for t in turns
    ]

    lessons = _lessons(session, skill)
    parts = test_out_parts(session, skill) if audit.test_out else child_titles(session, skill)
    pacing = _pacing(session)
    examined = audit.points
    asked = {p["title"] for p in examined}
    closed = closed_points(examined, turns)
    final = (
        audit.challenged
        or sum(1 for m in history if m["role"] == "user") >= audit.max_turns
        or (bool(examined) and len(closed) == len(examined))
    )
    def judge(provider: LLMProvider = auditor_provider) -> AuditorTurnResult:
        return Auditor(provider).next_turn(
            skill.title,
            skill.description,
            history,
            node_type=skill.node_type,
            lessons=lessons,
            max_turns=audit.max_turns,
            position=audit.node_position,
            child_titles=parts,
            pacing=pacing,
            # The Challenger's question was the last one: this answer gets the verdict.
            after_challenge=audit.challenged,
            test_out=bool(audit.test_out),
            points=examined,
            settled=[p["title"] for p in skill.points if p["title"] not in asked] if examined else None,
            closed=closed,
            audience=audit.audience or audit_style.DEFAULT_STYLE[0],
            depth=audit.depth if audit.depth is not None else audit_style.DEFAULT_STYLE[1],
        )

    try:
        result = judge()
    except Exception as exc:
        raise AuditorUnavailable from exc
    agreement = None
    challenge = None
    if result.is_verdict:
        # 只复核 pass，且每场审计至多一次（challenged 是那道收敛保证）。fail 不需要复核——
        # Challenger 的目标是推翻通过，对一个已经不通过的裁决无事可做。它和另外几票同时跑：
        # 用户等的是一次调用的时间；票数最后没判通过，它的结果就不用。
        may_challenge = bool(result.passed) and settings.challenger_enabled and not audit.challenged
        misconceptions = recent_misconceptions(session, settings.challenger_misconception_limit) if may_challenge else []
        second = second_auditor_provider()
        result, agreement, challenge = _voted(
            result,
            judge,
            final=final,
            alongside=(lambda: _challenge(skill, history, challenger_provider, misconceptions)) if may_challenge else None,
            second=(lambda: judge(second)) if second is not None else None,
        )

    if not result.is_verdict:
        return _save_question(session, audit, result.question, result.feedback, result.point)

    # 挑战不直接翻转裁决，而是变成最后一个追问：用户回应后由 Auditor 出最终裁决，那时
    # challenged 已为真。
    if result.passed and challenge is not None:
        audit.challenged = True
        session.add(audit)
        # What she said about the last answer still stands; the question is the Challenger's.
        return _save_question(session, audit, challenge, result.feedback)

    return _finalize(session, audit, skill, result, lessons, agreement)


def _save_answer(session: Session, audit: AuditSession, content: str) -> None:
    """Saves the answer, or replaces the previous one if it never got a reply.

    An answer without a reply after it means the last attempt failed (a 502, or the client gave
    up waiting) and this is the user sending it again, possibly edited.
    """
    turns = audit_turns(session, audit.id)
    if turns and turns[-1].role == TurnRole.user:
        turns[-1].content = content
        session.add(turns[-1])
    else:
        session.add(AuditTurn(session_id=audit.id, role=TurnRole.user, content=content))
    session.commit()


def _save_question(
    session: Session, audit: AuditSession, question: str, feedback: str | None = None, point: str | None = None
) -> ProbeOutcome:
    session.add(
        AuditTurn(session_id=audit.id, role=TurnRole.auditor, content=question, feedback=feedback, point=point)
    )
    session.commit()
    return ProbeOutcome(question=question, feedback=feedback, point=point)


def _lessons(session: Session, skill: SkillNode):
    # Memory Retriever 失败就当没有教训，审计照常进行。
    try:
        return retrieve_lessons(session, skill)
    except Exception:
        logger.warning("memory retriever failed, continuing without lessons", exc_info=True)
        return []


def _pacing(session: Session) -> str:
    try:
        return audit_pacing(session)
    except Exception:
        logger.warning("could not read the condition, using normal pacing", exc_info=True)
        return "normal"


def _challenge(
    skill: SkillNode, history: list[Message], provider: LLMProvider, misconceptions: list[str]
) -> str | None:
    """The Challenger's question if it overturns the pass; None if it upholds or fails. Takes
    no session: it runs beside the verdict's other votes, off the request's thread."""
    try:
        review = Challenger(provider).review(skill.title, skill.description, history, misconceptions)
    except Exception:
        logger.warning("challenger failed, upholding the auditor verdict", exc_info=True)
        return None
    if review.overturned:
        logger.info("challenger overturned a pass: %s", review.reason)
        return review.question
    return None


def _voted(
    first: AuditorTurnResult, judge, final: bool = False, alongside=None, second=None
) -> tuple[AuditorTurnResult, float | None, str | None]:
    """What the majority of `settings.auditor_votes` judgements of this answer says, the share
    of them that agreed, and the result of `alongside` (the Challenger, run at the same time so
    the wait is one call's).

    The same conversation judged again does not always end the same way near the line. Each
    judgement says pass, fail, or that she would ask on (a probe; on a final turn that is
    already a forced fail). Two that agree decide. With no two agreeing, or with most wanting
    to ask on, the audit goes on with a question when it may, and is not a pass when it may not:
    passing what should fail is the costlier mistake. A judgement that fails does not vote.

    `second` (AUDITOR_SECOND_PROVIDER): the same judgement on a model of another family, which
    takes the place of the last extra vote. Its mistakes are not the first model's, so it can
    break a tie the first model's own votes would repeat.
    """
    extra = settings.auditor_votes - 1

    def one(context: contextvars.Context, call):
        try:
            return context.run(call)  # the language and the usage log live in context variables
        except Exception:
            logger.warning("a call beside the verdict failed", exc_info=True)
            return None

    calls = [judge] * max(extra, 0)
    if second is not None and calls:
        calls[-1] = second
    calls += [alongside] if alongside is not None else []
    if not calls:
        return first, None, None
    with ThreadPoolExecutor(len(calls)) as pool:
        done = list(pool.map(one, [contextvars.copy_context() for _ in calls], calls))
    challenge = done.pop() if alongside is not None else None
    votes = [first, *(v for v in done if v is not None)]
    if len(votes) < 2:
        return first, None, challenge

    def said(vote: AuditorTurnResult) -> str:
        return ("pass" if vote.passed else "fail") if vote.is_verdict else "ask"

    counts = {kind: sum(1 for v in votes if said(v) == kind) for kind in ("pass", "fail", "ask")}
    if counts["pass"] * 2 > len(votes):
        outcome = "pass"
    elif counts["fail"] * 2 > len(votes):
        outcome = "fail"
    elif counts["ask"] and not final:
        outcome = "ask"
    else:
        outcome = "fail" if counts["fail"] else "ask"
    chosen = next(v for v in votes if said(v) == outcome)
    return chosen, counts[outcome] / len(votes), challenge if outcome == "pass" else None


def lesson_results(session: Session, audit_id: int) -> list[dict]:
    """The past lessons an audit touched, in the order recorded: held, or the mistake came back."""
    rows = session.exec(
        select(PrincipleCheck, Principle)
        .join(Principle, Principle.id == PrincipleCheck.principle_id)
        .where(PrincipleCheck.session_id == audit_id)
        .order_by(col(PrincipleCheck.id))
    ).all()
    return [{"principle_id": lesson.id, "title": lesson.title, "held": check.held} for check, lesson in rows]


def _finalize(
    session: Session,
    audit: AuditSession,
    skill: SkillNode,
    verdict: AuditorTurnResult,
    lessons: Sequence = (),
    agreement: float | None = None,
) -> VerdictOutcome:
    status = AuditStatus.passed if verdict.passed else AuditStatus.failed
    _claim(session, audit, status)

    # bandit 的上下文排除本场审计自己：它的结果不能泄漏进"裁决前"的状态判断。
    bucket = bandit.context_bucket(session, exclude_id=audit.id)
    tier = bandit.difficulty_tier(session, skill)

    audit.status = status
    audit.score = verdict.score
    audit.gaps_json = json.dumps(verdict.gaps or [], ensure_ascii=False)
    audit.comment = verdict.comment
    if verdict.points:
        audit.points_json = points.dump(verdict.points)
        # What held and what was missed stays on the node: the next audit starts from there.
        points.record_results(skill, verdict.points)
        session.add(skill)
    if verdict.evidence:
        audit.evidence_json = json.dumps(verdict.evidence, ensure_ascii=False)
    audit.agreement = agreement
    audit.judge_version = JUDGE_VERSION
    session.add(audit)
    # A lesson of this very audit's node may be among them; one made by this audit cannot be.
    for check in verdict.lesson_checks or []:
        if check["index"] < len(lessons):
            session.add(
                PrincipleCheck(principle_id=lessons[check["index"]].id, session_id=audit.id, held=check["held"])
            )
    # The learner model moves by what was settled; the bandit is rewarded with the progress
    # made, not with the pass.
    offset = audit_style.difficulty_offset(audit.audience, audit.depth)
    progress = learner.record(
        session, skill, bool(verdict.passed), verdict.points, agreement, tier, audit.id, offset=offset
    )
    if progress is not None:
        split = agreement is not None and agreement < 1
        weight = learner.SPLIT_WEIGHT if split else 1.0
        bandit.update_arm(session, bucket, tier, reward=progress, weight=weight)
        if audit.audience is not None and audit.style_context_json:
            x = json.loads(audit.style_context_json)
            audit_style.update(session, audit.audience, audit.depth, x, reward=progress, weight=weight)
    session.flush()

    outcome = VerdictOutcome(
        passed=bool(verdict.passed),
        score=verdict.score,
        gaps=list(verdict.gaps or []),
        comment=verdict.comment or "",
        feedback=verdict.feedback,
        points=list(verdict.points or []),
        evidence=audit.evidence,
        lessons=lesson_results(session, audit.id),
    )
    if verdict.passed:
        skill.status = SkillStatus.mastered
        skill.mastery_score = verdict.score
        session.add(skill)
        if audit.test_out:
            _master_under(session, skill)
        session.flush()

        outcome.unlocked_skill_ids = open_next(session, skill.course_id)
        sync_links(session)  # a course inside another one is mastered with its node
        outcome.reward_amount, outcome.reward_multiplier = compute_reward(session, skill)
        session.add(
            RewardEvent(session_id=audit.id, amount=outcome.reward_amount, multiplier=outcome.reward_multiplier)
        )

    session.commit()
    return outcome


def _master_under(session: Session, skill: SkillNode) -> None:
    """A passed challenge: every node under `skill` not mastered yet is, as tested out."""
    for node_id in descendant_ids(session, skill.id):
        node = session.get(SkillNode, node_id)
        if node is not None and node.status != SkillStatus.mastered:
            node.status = SkillStatus.mastered
            node.tested_out = True
            session.add(node)


def _claim(session: Session, audit: AuditSession, status: AuditStatus) -> None:
    """Closes the audit only if it is still active, in one statement; raises AuditClosed if
    another request got there first (both had passed the router's `active` check while their
    LLM calls ran)."""
    claimed = session.execute(
        update(AuditSession)
        .where(col(AuditSession.id) == audit.id, col(AuditSession.status) == AuditStatus.active)
        .values(status=status)
    )
    if claimed.rowcount != 1:
        session.rollback()
        raise AuditClosed(audit.id)
