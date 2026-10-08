"""审计流程的编排（Orchestrator，纯代码）：plan 6.6 的时序，一步不多一步不少。

提交一个回答时：保存回答 → Memory Retriever → Auditor →（pass 且没复核过：Challenger）→
保存 → 终判通过则解锁。路由层只管 404/400 这类 HTTP 语义，这里不碰 HTTP。

几条不能丢的规矩：

- 用户的回答先落库再调 Auditor。Auditor 挂了用户也不用重写一遍（路由返回 502）。重发时
  那条还没等到回复的回答被替换，而不是在它旁边再存一条（否则重复的回答会白占轮数上限）。
- 结算先原子地把会话从 active 改掉（`_claim`）：两个并发请求只有一个能结算，另一个得到
  AuditClosed（路由回 400），奖励和 bandit 不会记两次。
- Challenger 出任何问题都按维持原判处理——它只能收紧裁决，不能制造新的失败模式。
- 终判通过：节点 mastered 并写入 mastery_score；每个以它为 contains 父节点的 locked 节点
  变 available（任意一个父节点通过就够）；记录奖励。失败：节点状态不动。
"""

import json
import logging
from dataclasses import dataclass, field

from sqlalchemy import update
from sqlmodel import Session, col, select

from app.agents.auditor import Auditor, AuditorTurnResult
from app.agents.challenger import Challenger
from app.agents.memory_retriever import recent_misconceptions, retrieve_lessons
from app.config import settings
from app.llm.base import LLMProvider, Message
from app.models import (
    AuditSession,
    AuditStatus,
    AuditTurn,
    NodePosition,
    NodeType,
    RewardEvent,
    SkillNode,
    SkillStatus,
    TurnRole,
)
from app.i18n import join_list, quote, t
from app.services import bandit
from app.services.condition import audit_pacing
from app.services.incentive import compute_reward
from app.services.tree import child_titles, node_position, open_next

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


@dataclass
class VerdictOutcome:
    passed: bool
    score: int
    gaps: list[str]
    comment: str
    unlocked_skill_ids: list[int] = field(default_factory=list)
    reward_amount: int | None = None
    reward_multiplier: float | None = None


TurnOutcome = ProbeOutcome | VerdictOutcome


def opening_question(skill: SkillNode, position: NodePosition, children: list[str]) -> str:
    if skill.node_type == NodeType.task:
        return t("opening_task", title=quote(skill.title))
    if position == NodePosition.root:
        return t("opening_root", title=quote(skill.title))
    if position == NodePosition.branch:
        return t("opening_branch", title=quote(skill.title), children=join_list(children))
    return t("opening_leaf", title=quote(skill.title))


def max_turns_for(node_type: NodeType, mode: str) -> int:
    base = settings.audit_max_turns if node_type == NodeType.concept else settings.task_max_turns
    return base * 2 if mode == "night" else base


def audit_turns(session: Session, audit_id: int) -> list[AuditTurn]:
    return list(
        session.exec(
            select(AuditTurn)
            .where(AuditTurn.session_id == audit_id)
            .order_by(col(AuditTurn.created_at), col(AuditTurn.id))
        ).all()
    )


def start_audit(session: Session, skill: SkillNode, mode: str) -> tuple[AuditSession, str]:
    position = node_position(session, skill)
    audit = AuditSession(
        skill_id=skill.id,
        node_position=position,
        status=AuditStatus.active,
        max_turns=max_turns_for(skill.node_type, mode),
    )
    session.add(audit)
    session.flush()

    question = opening_question(skill, position, child_titles(session, skill))
    session.add(AuditTurn(session_id=audit.id, role=TurnRole.auditor, content=question))
    session.commit()
    session.refresh(audit)
    return audit, question


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

    history: list[Message] = [
        {"role": "user" if t.role == TurnRole.user else "assistant", "content": t.content}
        for t in audit_turns(session, audit.id)
    ]

    lessons = _lessons(session, skill)
    parts = child_titles(session, skill)
    pacing = _pacing(session)
    try:
        result = Auditor(auditor_provider).next_turn(
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
        )
    except Exception as exc:
        raise AuditorUnavailable from exc

    if not result.is_verdict:
        return _save_question(session, audit, result.question)

    # 只复核 pass，且每场审计至多一次（challenged 是那道收敛保证）。fail 不需要复核——
    # Challenger 的目标是推翻通过，对一个已经不通过的裁决无事可做。挑战不直接翻转裁决，
    # 而是变成最后一个追问：用户回应后由 Auditor 出最终裁决，那时 challenged 已为真。
    if result.passed and settings.challenger_enabled and not audit.challenged:
        question = _challenge(session, skill, history, challenger_provider)
        if question is not None:
            audit.challenged = True
            session.add(audit)
            return _save_question(session, audit, question)

    return _finalize(session, audit, skill, result)


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


def _save_question(session: Session, audit: AuditSession, question: str) -> ProbeOutcome:
    session.add(AuditTurn(session_id=audit.id, role=TurnRole.auditor, content=question))
    session.commit()
    return ProbeOutcome(question=question)


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


def _challenge(session: Session, skill: SkillNode, history: list[Message], provider: LLMProvider) -> str | None:
    """The Challenger's question if it overturns the pass; None if it upholds or fails."""
    try:
        review = Challenger(provider).review(
            skill.title,
            skill.description,
            history,
            recent_misconceptions(session, settings.challenger_misconception_limit),
        )
    except Exception:
        logger.warning("challenger failed, upholding the auditor verdict", exc_info=True)
        return None
    if review.overturned:
        logger.info("challenger overturned a pass: %s", review.reason)
        return review.question
    return None


def _finalize(session: Session, audit: AuditSession, skill: SkillNode, verdict: AuditorTurnResult) -> VerdictOutcome:
    status = AuditStatus.passed if verdict.passed else AuditStatus.failed
    _claim(session, audit, status)

    # bandit 的上下文排除本场审计自己：它的结果不能泄漏进"裁决前"的状态判断。
    bucket = bandit.context_bucket(session, exclude_id=audit.id)
    tier = bandit.difficulty_tier(session, skill)

    audit.status = status
    audit.score = verdict.score
    audit.gaps_json = json.dumps(verdict.gaps or [], ensure_ascii=False)
    audit.comment = verdict.comment
    session.add(audit)
    bandit.update_arm(session, bucket, tier, reward=bool(verdict.passed))

    outcome = VerdictOutcome(
        passed=bool(verdict.passed),
        score=verdict.score,
        gaps=list(verdict.gaps or []),
        comment=verdict.comment or "",
    )
    if verdict.passed:
        skill.status = SkillStatus.mastered
        skill.mastery_score = verdict.score
        session.add(skill)
        session.flush()

        outcome.unlocked_skill_ids = open_next(session, skill.course_id)
        outcome.reward_amount, outcome.reward_multiplier = compute_reward(session, skill)
        session.add(
            RewardEvent(session_id=audit.id, amount=outcome.reward_amount, multiplier=outcome.reward_multiplier)
        )

    session.commit()
    return outcome


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
