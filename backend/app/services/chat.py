"""Chat orchestration (contract section 5, endpoints 18-20).

AD-7: the front desk only classifies. This module runs the existing pipelines (course
generation, check-in, study plan, briefing) by calling the same service functions the plain
REST endpoints use. Audits never start from chat.

What the user says in a check-in or a plain chat also goes to the Fact Keeper (`remember`, run
after the response by the router; contract #40).

A message routed to `none` is answered by the Guide (app/agents/guide.py) with the chat so far,
older related lines, today's check-in, the condition, today's quests, the last audits, lessons and
the lasting facts (`guide_context`, no LLM); if it fails, the front desk's own reply stands. A
logged check-in gets one Guide line on what it changes today. Both are agent `front_desk`: to the
client the Guide is the front desk.

A pipeline failure is not an error: the second assistant message explains it in English and the
endpoint still answers 200. Only a front desk failure fails the request (FrontDeskUnavailable),
and by then the user's message is already saved.
"""

import json
import logging
import re
from collections.abc import Callable
from pathlib import PurePath

from sqlmodel import Session, col, select

from app.i18n import join_list, language_of, quote, t, use_language
from app.agents.front_desk import FrontDesk, FrontDeskResult
from app.agents.guide import Guide, Turn
from app.llm import decisions
from app.llm.base import LLMProvider
from app.agents.planner import SyllabusText
from app.models import (
    AuditSession,
    AuditStatus,
    ChatMessage,
    Course,
    DailyCheckIn,
    EdgeKind,
    Principle,
    SkillNode,
    SkillStatus,
    Upload,
)
from app.schemas import (
    ChatMessageOut,
    ChatSuggestionOut,
    CheckInRequest,
    CHECKIN_FIELDS,
    CheckInResponse,
    CourseOut,
)
from app.search.base import SearchProvider
from app.services.courses import live_courses, live_nodes
from app.services import briefing as briefing_service
from app.services import checkin as checkin_service
from app.agents.memory_retriever import retrieve_lessons
from app.services import course_generation, day_plan, facts as facts_service, journal, planning
from app.services.condition import current_condition
from app.services.briefing import BriefingFailed
from app.services.course_generation import CourseGenerationError
from app.services.planning import NoAvailableNode, PlanFailed

logger = logging.getLogger(__name__)

ProviderFor = Callable[[str], LLMProvider]
# The text Guide's lines are the front desk's too: the client knows the Guide by that name.
GUIDE_AGENT = "front_desk"
Remember = Callable[[str], None]

DEFAULT_DIFFICULTY = "standard"


class FrontDeskUnavailable(Exception):
    """The front desk agent failed; the user message has been saved."""


class UploadNotFound(Exception):
    """An id in `upload_ids` does not exist."""


def load_uploads(session: Session, upload_ids: list[int] | None) -> list[Upload]:
    """The uploads for `upload_ids`, in request order without duplicates. Raises UploadNotFound."""
    uploads: list[Upload] = []
    for upload_id in dict.fromkeys(upload_ids or []):
        upload = session.get(Upload, upload_id)
        if upload is None:
            raise UploadNotFound(upload_id)
        uploads.append(upload)
    return uploads


def syllabus_text(uploads: list[Upload]) -> SyllabusText:
    """One document for the Planner. A single file is passed as is; several are labelled by name."""
    if len(uploads) == 1:
        return SyllabusText(source=uploads[0].filename, text=uploads[0].text)
    return SyllabusText(
        source=", ".join(u.filename for u in uploads),
        text="\n\n".join(f"[{u.filename}]\n{u.text}" for u in uploads),
    )


# ---------------------------------------------------------------- persistence

def _save(session: Session, role: str, content: str, agent: str | None = None, action: dict | None = None) -> ChatMessage:
    message = ChatMessage(
        role=role,
        content=content,
        agent=agent,
        action_json=json.dumps(action, ensure_ascii=False) if action is not None else None,
    )
    session.add(message)
    session.commit()
    session.refresh(message)
    return message


def message_out(message: ChatMessage) -> ChatMessageOut:
    return ChatMessageOut(
        id=message.id,
        role=message.role,
        content=message.content,
        agent=message.agent,
        action=json.loads(message.action_json) if message.action_json else None,
        created_at=message.created_at,
    )


def history(session: Session, limit: int) -> list[ChatMessageOut]:
    """The last `limit` messages, oldest first."""
    rows = session.exec(select(ChatMessage).order_by(col(ChatMessage.id).desc()).limit(limit)).all()
    return [message_out(m) for m in reversed(rows)]


# ---------------------------------------------------------------- node lookup

def _nodes_newest_course_first(session: Session) -> list[SkillNode]:
    return list(
        session.exec(
            live_nodes().order_by(col(Course.created_at).desc(), col(Course.id).desc(), SkillNode.id)
        ).all()
    )


def resolve_node(nodes: list[SkillNode], text: str) -> SkillNode | None:
    """Exact title first, then a title containing the text, then a title found inside the text.

    `nodes` is already ordered newest course first, so the first match wins.
    """
    wanted = text.strip().casefold()
    if not wanted:
        return None
    for matches in (
        lambda title: title == wanted,
        lambda title: wanted in title,
        lambda title: title in wanted,
    ):
        for node in nodes:
            if node.title.strip() and matches(node.title.strip().casefold()):
                return node
    return None


# ---------------------------------------------------------------- the intent pipelines

def _run_generate_course(
    session: Session,
    topic: str,
    provider_for: ProviderFor,
    search_provider_for: Callable[[], SearchProvider],
    syllabus_text: SyllabusText | None = None,
) -> ChatMessage:
    try:
        generated = course_generation.generate_course(
            session,
            topic=topic,
            difficulty=DEFAULT_DIFFICULTY,
            search_syllabus=True,
            planner_provider=provider_for("planner"),
            syllabus_provider=provider_for("syllabus_finder"),
            search_provider=search_provider_for(),
            syllabus_text=syllabus_text,
        )
    except CourseGenerationError:
        logger.warning("chat: course generation failed", exc_info=True)
        session.rollback()
        return _save(session, "assistant", t("world_failed"), "front_desk")
    # The world is named after the course's root: the node nothing contains.
    contained = {e.to_id for e in generated.edges if e.kind == EdgeKind.contains}
    root = next((n for n in generated.nodes if n.id not in contained), generated.nodes[0])
    return _save(
        session,
        "assistant",
        t("world_merged", title=quote(root.title), added=generated.added)
        if generated.merged
        else t("world_ready", title=quote(root.title), count=len(generated.nodes)),
        "planner",
        {
            "type": "course",
            "course": CourseOut.model_validate(generated.course).model_dump(mode="json"),
            "node_count": len(generated.nodes),
        },
    )


def _checkin_summary(result) -> str:
    c = result.checkin
    parts = []
    if c.sleep_hours is not None:
        parts.append(t("checkin_sleep", hours=c.sleep_hours))
    if c.exercised is not None:
        parts.append(t("checkin_exercise_yes" if c.exercised else "checkin_exercise_no"))
    if c.diet_note:
        parts.append(t("checkin_meals", note=c.diet_note))
    if c.focus is not None:
        parts.append(t("checkin_focus", value=c.focus))
    if c.stress is not None:
        parts.append(t("checkin_stress", value=c.stress))
    if not parts:
        return t("checkin_nothing")
    return t("checkin_logged", parts=" · ".join(parts))


def _record_checkin(session: Session, message: str, provider_for: ProviderFor) -> tuple[ChatMessage, CheckInResponse]:
    result = checkin_service.record_checkin(session, CheckInRequest(transcript=message), provider_for)
    saved = _save(
        session,
        "assistant",
        _checkin_summary(result),
        "checkin_converter",
        {"type": "checkin", "result": result.model_dump(mode="json")},
    )
    return saved, result


def _run_checkin(session: Session, message: str, provider_for: ProviderFor) -> ChatMessage:
    return _record_checkin(session, message, provider_for)[0]


def _run_plan(session: Session, provider_for: ProviderFor) -> ChatMessage:
    try:
        plan = planning.generate_plan(session, provider_for)
    except NoAvailableNode:
        return _save(session, "assistant", t("no_node_ready"), "front_desk")
    except PlanFailed:
        session.rollback()
        return _save(session, "assistant", t("plan_failed"), "front_desk")
    titles = join_list([quote(s.skill_title) for s in plan.steps])
    # With the focus used up there are no quests, only the line saying so.
    line = f"{t('todays_quests', titles=titles)} {plan.summary}".strip() if plan.steps else plan.summary
    return _save(
        session,
        "assistant",
        line,
        "recommender",
        {"type": "plan", "plan": plan.model_dump(mode="json")},
    )


def _run_briefing(session: Session, provider_for: ProviderFor) -> ChatMessage:
    try:
        briefing = briefing_service.narrate(session, provider_for)
    except BriefingFailed:
        session.rollback()
        return _save(session, "assistant", t("briefing_failed"), "front_desk")
    return _save(
        session,
        "assistant",
        briefing.narrative or "",
        "narrator",
        {"type": "briefing", "briefing": briefing.model_dump(mode="json")},
    )


# ---------------------------------------------------------------- audit review

REVIEW_AUDITS = 10  # how many finished audits the Guide looks back over
REVIEW_GAPS = 3


def audit_review(session: Session) -> tuple[str, dict | None]:
    """What the user got wrong lately, from the stored audits (no LLM): the gaps of the last
    failed audit with what is right, and how many of the recent ones passed. The action opens
    that audit's replay."""
    rows = session.exec(
        select(AuditSession, SkillNode)
        .join(SkillNode, SkillNode.id == AuditSession.skill_id)
        .join(Course, Course.id == SkillNode.course_id)
        .where(col(Course.archived_at).is_(None), AuditSession.status != AuditStatus.active)
        .order_by(col(AuditSession.created_at).desc(), col(AuditSession.id).desc())
        .limit(REVIEW_AUDITS)
    ).all()
    if not rows:
        return t("audit_review_none"), None
    lines: list[str] = []
    action = None
    failed = next(((a, n) for a, n in rows if a.status == AuditStatus.failed), None)
    if failed is not None:
        audit, node = failed
        lines.append(t("audit_review_failed", title=quote(node.title)))
        evidence = audit.evidence[:REVIEW_GAPS]
        for item in evidence:
            lines.append(f"- {item['gap']} — {item['right']}" if item.get("right") else f"- {item['gap']}")
        if not evidence:
            lines.append(t("audit_review_no_gaps"))
        action = {"type": "navigate", "scene": "audit", "audit_id": audit.id}
    else:
        lines.append(t("audit_review_clean"))
    passed = sum(1 for a, _ in rows if a.status == AuditStatus.passed)
    lines.append(t("audit_review_count", passed=passed, total=len(rows)))
    return "\n".join(lines), action


# ---------------------------------------------------------------- the Guide's memory (no LLM)

ROUTER_TURNS = 6  # chat lines before the message the front desk sees
GUIDE_TURNS = 12  # ... and the Guide
OLDER_SCAN = 300  # older lines searched for ones related to the message
OLDER_TURNS = 3
OLDER_MIN_SHARED = 2
GUIDE_AUDITS = 3
GUIDE_LESSONS = 3
GUIDE_TITLES = 40
SAID_CHARS = 600
# Who said a line, as the agents read the chat.
_SPEAKERS = {
    "front_desk": "Guide",
    "checkin_converter": "Check-in",
    "recommender": "Quests",
    "narrator": "Status",
    "planner": "World builder",
}
_WORD_RE = re.compile(r"[a-z0-9]{3,}")
_CJK_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uac00-\ud7a3]+")
_STOP = {"the", "and", "you", "what", "how", "that", "this", "for", "with", "are", "was", "have", "today", "can", "did"}


def _turn(m: ChatMessage) -> Turn:
    return ("User", m.content) if m.role == "user" else (_SPEAKERS.get(m.agent or "front_desk", m.agent or "Guide"), m.content)


def _before(session: Session, before_id: int, limit: int, offset: int = 0) -> list[ChatMessage]:
    """Up to `limit` messages before `before_id` (skipping the `offset` nearest), oldest first."""
    rows = session.exec(
        select(ChatMessage)
        .where(col(ChatMessage.id) < before_id)
        .order_by(col(ChatMessage.id).desc())
        .offset(offset)
        .limit(limit)
    ).all()
    return list(reversed(rows))


def recent_turns(session: Session, before_id: int, limit: int) -> list[Turn]:
    return [_turn(m) for m in _before(session, before_id, limit)]


def _keys(text: str) -> set[str]:
    """Words of three letters or more, and every pair of neighbouring CJK / Hangul characters."""
    lowered = text.casefold()
    keys = {w for w in _WORD_RE.findall(lowered) if w not in _STOP}
    for run in _CJK_RE.findall(lowered):
        keys.update(run[i : i + 2] for i in range(len(run) - 1))
    return keys


def older_related(session: Session, before_id: int, message: str) -> list[Turn]:
    """Lines older than the Guide's window that share the most words with the message (at least
    OLDER_MIN_SHARED), oldest first: the chat beyond the last GUIDE_TURNS is searched, not lost."""
    wanted = _keys(message)
    if not wanted:
        return []
    scored = []
    for m in _before(session, before_id, OLDER_SCAN, offset=GUIDE_TURNS):
        shared = len(wanted & _keys(m.content))
        if shared >= OLDER_MIN_SHARED:
            scored.append((shared, m.id, m))
    best = sorted(scored, key=lambda x: (x[0], x[1]), reverse=True)[:OLDER_TURNS]
    return [_turn(m) for _, _, m in sorted(best, key=lambda x: x[1])]


def _checkin_facts(row: DailyCheckIn | None) -> dict | None:
    if row is None:
        return None
    return {
        "date": row.date.isoformat(),
        "sleep_hours": row.sleep_hours,
        "sleep_quality_1_5": row.sleep_quality,
        "exercised": row.exercised,
        "exercise_minutes": row.exercise_minutes,
        "meals": row.diet_note,
        "focus_1_5": row.focus,
        "stress_1_5": row.stress,
        "weight_kg": row.weight_kg,
        "said": (row.transcript or "")[-SAID_CHARS:] or None,
    }


def _condition_facts(session: Session) -> dict:
    c = current_condition(session)
    return {
        "flag": c.flag,
        "checkins_used": c.days,
        "avg_sleep_hours": round(c.avg_sleep_hours, 1) if c.avg_sleep_hours is not None else None,
        "avg_stress_1_5": round(c.avg_stress, 1) if c.avg_stress is not None else None,
        "audit_pacing": "light" if c.flag == "low" else "normal",
    }


def _todays_quests(session: Session) -> list[dict] | None:
    """The quests of today's latest plan, None when today has none (no LLM: the stored plan)."""
    plan = planning.current_plan(session)
    if plan is None or json.loads(plan.context_json).get("date") != day_plan.now().date().isoformat():
        return None
    return [
        {"node": s.get("skill_title"), "kind": s.get("kind", "learn"), "minutes": s.get("minutes")}
        for s in json.loads(plan.steps_json)
    ]


def _recent_audits(session: Session) -> list[dict]:
    rows = session.exec(
        select(AuditSession, SkillNode)
        .join(SkillNode, SkillNode.id == AuditSession.skill_id)
        .join(Course, Course.id == SkillNode.course_id)
        .where(col(Course.archived_at).is_(None), AuditSession.status != AuditStatus.active)
        .order_by(col(AuditSession.created_at).desc(), col(AuditSession.id).desc())
        .limit(GUIDE_AUDITS)
    ).all()
    return [
        {
            "node": node.title,
            "result": audit.status.value,
            "date": audit.created_at.date().isoformat(),
            "gaps": [e["gap"] for e in audit.evidence[:REVIEW_GAPS]],
        }
        for audit, node in rows
    ]


def _lessons(session: Session, nodes: list[SkillNode], message: str) -> list[dict]:
    """The lessons of a node the message names (memory_retriever), else the latest ones."""
    lowered = message.casefold()
    named = next((n for n in nodes if len(n.title.strip()) >= 2 and n.title.strip().casefold() in lowered), None)
    if named is not None:
        rows = retrieve_lessons(session, named, GUIDE_LESSONS)
    else:
        rows = session.exec(
            select(Principle).order_by(col(Principle.created_at).desc(), col(Principle.id).desc()).limit(GUIDE_LESSONS)
        ).all()
    return [{"title": p.title, "lesson": p.body, "misconception": p.misconception} for p in rows]


def guide_context(session: Session, nodes: list[SkillNode], message: str = "") -> dict:
    """What the Guide is told about the player, all from the database."""
    return {
        "today": day_plan.now().date().isoformat(),
        "todays_checkin": _checkin_facts(checkin_service.todays_checkin(session)),
        "condition": _condition_facts(session),
        "todays_quests": _todays_quests(session),
        "recent_audits": _recent_audits(session),
        "lessons": _lessons(session, nodes, message),
        "lasting_facts": facts_service.for_coach(session),
        "nodes": list(dict.fromkeys(n.title for n in nodes))[:GUIDE_TITLES],
    }


def _guide_reply(
    session: Session, message: str, before_id: int, nodes: list[SkillNode], draft: str, provider_for: ProviderFor
) -> str | None:
    """The Guide's answer, or None when it fails (the front desk's reply `draft` stands)."""
    try:
        return Guide(provider_for("guide")).reply(
            message,
            recent_turns(session, before_id, GUIDE_TURNS),
            older_related(session, before_id, message),
            guide_context(session, nodes, message),
            draft,
        )
    except Exception:
        logger.warning("guide failed, keeping the front desk's reply", exc_info=True)
        session.rollback()
        return None


def _checkin_feedback(session: Session, message: str, provider_for: ProviderFor) -> ChatMessage | None:
    """One Guide line on what the check-in just logged changes today; None when it fails."""
    context = {
        "checkin": _checkin_facts(checkin_service.todays_checkin(session)),
        "condition": _condition_facts(session),
        "todays_quests": _todays_quests(session),
        "lasting_facts": facts_service.for_coach(session),
    }
    try:
        line = Guide(provider_for("guide")).checkin_feedback(message, context)
    except Exception:
        logger.warning("guide check-in feedback failed, leaving it out", exc_info=True)
        session.rollback()
        return None
    return _save(session, "assistant", line, GUIDE_AGENT)


# ---------------------------------------------------------------- the endpoint

def handle_message(
    session: Session,
    message: str,
    provider_for: ProviderFor,
    search_provider_for: Callable[[], SearchProvider],
    uploads: list[Upload] | None = None,
    course_topic: str | None = None,
    remember: Remember | None = None,
    log_said: Remember | None = None,
) -> list[ChatMessageOut]:
    """`course_topic` (the tutorial) builds a course straight away: no front desk call, so the
    result does not hang on how the message would be classified.

    `log_said` (checkin.said_later): a plain chat message that mentions the day in passing ("I had
    ramen, how many calories is that?") is offered to the day's check-in after the response, behind
    the Decisions gate; only when the gate is available, so it never adds a converter call to
    every message."""
    user = _save(session, "user", message)  # kept even if the front desk fails

    if course_topic is not None:
        topic = course_topic.strip() or PurePath(uploads[0].filename).stem
        first = _save(session, "assistant", t("build_world", topic=quote(topic)), "front_desk")
        syllabus = syllabus_text(uploads) if uploads else None
        built = _run_generate_course(session, topic, provider_for, search_provider_for, syllabus)
        return [message_out(m) for m in (user, first, built)]

    nodes = _nodes_newest_course_first(session)
    # The Guide answers in the language the user wrote in, whatever the interface is set to
    # (language_of is the detector audits use; None keeps the request's language).
    spoken = language_of(message)
    try:
        desk = FrontDesk(provider_for("front_desk"), decide=decisions.decide if decisions.available() else None)
        with use_language(spoken):
            routed: FrontDeskResult = desk.route(
                message, [n.title for n in nodes], recent_turns(session, user.id, ROUTER_TURNS)
            )
    except Exception as exc:
        logger.warning("front desk failed", exc_info=True)
        session.rollback()
        raise FrontDeskUnavailable from exc

    content, action = routed.reply, None
    intent = routed.intent
    if remember is not None and (intent == "checkin" or (intent == "none" and not uploads)):
        remember(message)
    if log_said is not None and intent == "none" and not uploads and decisions.available():
        log_said(message)
    topic = str(routed.args.get("topic") or "").strip()

    if intent == "open_skill":
        node = resolve_node(nodes, str(routed.args.get("skill") or ""))
        if node is None:
            content = t("which_node")
        else:
            action = {"type": "navigate", "scene": "skill", "skill_id": node.id}
    elif intent == "open_map":
        action = {"type": "navigate", "scene": "map"}
    elif intent == "audit_review":
        with use_language(spoken):
            content, action = audit_review(session)
    elif intent == "none" and not uploads:
        with use_language(spoken):
            content = _guide_reply(session, message, user.id, nodes, content, provider_for) or content

    # Saved before the pipeline runs, so ids stay in reading order: user, front desk, result.
    first = _save(session, "assistant", content, "front_desk", action)
    result: list[ChatMessage] = [user, first]

    if uploads and intent in ("generate_course", "none"):
        # The file replaces the Syllabus Finder: the topic falls back to the first file's name.
        topic = topic or PurePath(uploads[0].filename).stem
        result.append(_run_generate_course(session, topic, provider_for, search_provider_for, syllabus_text(uploads)))
    elif intent == "generate_course" and topic:
        result.append(_run_generate_course(session, topic, provider_for, search_provider_for))
    elif intent == "checkin":
        logged, checked = _record_checkin(session, message, provider_for)
        result.append(logged)
        if checked.missing_fields != list(CHECKIN_FIELDS):  # it logged something
            with use_language(spoken):
                feedback = _checkin_feedback(session, message, provider_for)
            if feedback is not None:
                result.append(feedback)
    elif intent == "plan":
        result.append(_run_plan(session, provider_for))
    elif intent == "briefing":
        result.append(_run_briefing(session, provider_for))
    return [message_out(m) for m in result]


# ---------------------------------------------------------------- the realtime Guide (contract #36)

# The intents the realtime Guide runs as tools: the front desk's, minus "none" (it talks itself).
ACTIONS = ("generate_course", "open_skill", "checkin", "plan", "briefing", "open_map")  # audit_review: chat only
# The realtime Guide is the Guide: its lines are the front desk's in the history.
VOICE_AGENT = "front_desk"


def handle_action(
    session: Session,
    intent: str,
    args: dict,
    said: str,
    provider_for: ProviderFor,
    search_provider_for: Callable[[], SearchProvider],
    remember: Remember | None = None,
) -> list[ChatMessageOut]:
    """One tool call of the realtime Guide: the intent is already chosen, so no front desk call.

    Saves what the user said (when given), then runs the intent like a chat message would;
    returns [user?, result...]. The Guide's own spoken reply is logged afterwards (log_voice).
    """
    if intent not in ACTIONS:
        raise ValueError(f"unknown intent {intent!r}")
    result: list[ChatMessage] = []
    if said.strip():
        result.append(_save(session, "user", said.strip()))
    if intent == "generate_course":
        topic = str(args.get("topic") or "").strip()
        if not topic:
            raise ValueError("generate_course needs a topic")
        result.append(_run_generate_course(session, topic, provider_for, search_provider_for))
    elif intent == "open_skill":
        node = resolve_node(_nodes_newest_course_first(session), str(args.get("skill") or ""))
        if node is None:
            result.append(_save(session, "assistant", t("which_node"), VOICE_AGENT))
        else:
            result.append(_save(
                session, "assistant", t("opening_node", title=quote(node.title)), VOICE_AGENT,
                {"type": "navigate", "scene": "skill", "skill_id": node.id},
            ))
    elif intent == "open_map":
        result.append(_save(session, "assistant", t("opening_map"), VOICE_AGENT, {"type": "navigate", "scene": "map"}))
    elif intent == "checkin":
        # The Guide's summary covers what was said earlier in the talk; the user's last words are
        # their own. Both go to the converter, which keeps only what was said.
        summary = str(args.get("said") or "").strip()
        words = "\n".join(dict.fromkeys(w for w in (summary, said.strip()) if w))
        if not words:
            raise ValueError("checkin needs what the user said")
        result.append(_run_checkin(session, words, provider_for))
        if remember is not None:
            remember(words)
    elif intent == "plan":
        result.append(_run_plan(session, provider_for))
    elif intent == "briefing":
        result.append(_run_briefing(session, provider_for))
    return [message_out(m) for m in result]


def log_voice(
    session: Session,
    lines: list[tuple[str, str]],
    remember: Remember | None = None,
    log_said: Remember | None = None,
) -> list[ChatMessageOut]:
    """Keeps a spoken exchange with the realtime Guide in the history. No LLM here; what the user
    said goes to `remember` (lasting facts) and `log_said` (a check-in when it reports the day and
    the Guide did not log it: the client only sends lines no tool call has read)."""
    saved = [
        _save(session, role, content.strip(), VOICE_AGENT if role == "assistant" else None)
        for role, content in lines
        if content.strip()
    ]
    said = "\n".join(m.content for m in saved if m.role == "user")
    if remember is not None and said:
        remember(said)
    if log_said is not None and said:
        log_said(said)
    return [message_out(m) for m in saved]


REFLECTION_ACK = "Noted. It's in your journal."


def handle_reflection(session: Session, prompt: str, answer: str) -> list[ChatMessageOut]:
    """The user answers a reflection prompt (contract section 6). No LLM.

    Saves the prompt as a front desk message, the user's answer, a JournalEntry and the
    acknowledgement; returns [prompt, answer, ack].
    """
    asked = _save(session, "assistant", prompt, "front_desk")
    user = _save(session, "user", answer)
    journal.add_entry(session, prompt, answer)
    ack = _save(session, "assistant", REFLECTION_ACK, "front_desk")
    return [message_out(m) for m in (asked, user, ack)]


# ---------------------------------------------------------------- suggestions (endpoint 20)

def suggestions(session: Session) -> list[ChatSuggestionOut]:
    """At most 2 chips, in the contract's order: check-in or reflection, then continue learning."""
    items: list[ChatSuggestionOut] = []

    if checkin_service.todays_checkin(session) is None:
        items.append(ChatSuggestionOut(label=t("suggest_checkin_label"), message=t("suggest_checkin_message"), skill_id=None))
    else:
        # Once the day is logged, item 1 is the current time window's reflection prompt (unless answered).
        prompt = journal.current_prompt(session)
        if prompt is not None:
            items.append(ChatSuggestionOut(label=prompt, message="", skill_id=None, reflection=True))

    # Continue the node of the most recent audit while it is not mastered ...
    last = session.exec(
        live_nodes()
        .join(AuditSession, AuditSession.skill_id == SkillNode.id)
        .order_by(col(AuditSession.created_at).desc(), col(AuditSession.id).desc())
    ).first()
    if last is not None and last.status != SkillStatus.mastered:
        label = t("suggest_continue", title=quote(last.title))
        items.append(ChatSuggestionOut(label=label, message=label, skill_id=last.id))
        return items

    # ... otherwise start the newest course's lowest-id available node.
    course = session.exec(live_courses().order_by(col(Course.created_at).desc(), col(Course.id).desc())).first()
    node = None
    if course is not None:
        node = session.exec(
            select(SkillNode)
            .where(SkillNode.course_id == course.id, SkillNode.status == SkillStatus.available)
            .order_by(SkillNode.id)
        ).first()
    if node is not None:
        label = t("suggest_start", title=quote(node.title))
        items.append(ChatSuggestionOut(label=label, message=label, skill_id=node.id))
    else:
        # No course (or nothing left to open): the client only focuses the input.
        items.append(ChatSuggestionOut(label=t("suggest_learn"), message="", skill_id=None))
    return items
