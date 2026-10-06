"""Chat orchestration (contract section 5, endpoints 18-20).

AD-7: the front desk only classifies. This module runs the existing pipelines (course
generation, check-in, study plan, briefing) by calling the same service functions the plain
REST endpoints use. Audits never start from chat.

A pipeline failure is not an error: the second assistant message explains it in English and the
endpoint still answers 200. Only a front desk failure fails the request (FrontDeskUnavailable),
and by then the user's message is already saved.
"""

import json
import logging
from collections.abc import Callable
from pathlib import PurePath

from sqlmodel import Session, col, select

from app.agents.front_desk import FrontDesk, FrontDeskResult
from app.llm.base import LLMProvider
from app.agents.planner import SyllabusText
from app.models import AuditSession, ChatMessage, Course, SkillNode, SkillStatus, Upload
from app.schemas import (
    ChatMessageOut,
    ChatSuggestionOut,
    CheckInRequest,
    CourseOut,
)
from app.search.base import SearchProvider
from app.services import briefing as briefing_service
from app.services import checkin as checkin_service
from app.services import course_generation, journal, planning
from app.services.briefing import BriefingFailed
from app.services.course_generation import CourseGenerationError
from app.services.planning import NoAvailableNode, PlanFailed

logger = logging.getLogger(__name__)

ProviderFor = Callable[[str], LLMProvider]

DEFAULT_NODE_COUNT = 12
DEFAULT_MAX_DEPTH = 4
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


def _syllabus_text(uploads: list[Upload]) -> SyllabusText:
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
            select(SkillNode)
            .join(Course, Course.id == SkillNode.course_id)
            .order_by(col(Course.created_at).desc(), col(Course.id).desc(), SkillNode.id)
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
            node_count=DEFAULT_NODE_COUNT,
            max_depth=DEFAULT_MAX_DEPTH,
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
        return _save(session, "assistant", "I couldn't build that world. Please try again in a moment.", "front_desk")
    root = next((n for n in generated.nodes if n.status == SkillStatus.available), generated.nodes[0])
    return _save(
        session,
        "assistant",
        f"Your world “{root.title}” is ready — {len(generated.nodes)} nodes.",
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
        parts.append(f"sleep {c.sleep_hours} h")
    if c.exercised is not None:
        parts.append(f"exercise {'yes' if c.exercised else 'no'}")
    if c.diet_note:
        parts.append(f"meals {c.diet_note}")
    if c.focus is not None:
        parts.append(f"focus {c.focus}/5")
    if c.stress is not None:
        parts.append(f"stress {c.stress}/5")
    if not parts:
        return "I couldn't find anything to log. Tell me about sleep, exercise or meals."
    return "Logged: " + " · ".join(parts)


def _run_checkin(session: Session, message: str, provider_for: ProviderFor) -> ChatMessage:
    result = checkin_service.record_checkin(session, CheckInRequest(transcript=message), provider_for)
    return _save(
        session,
        "assistant",
        _checkin_summary(result),
        "checkin_converter",
        {"type": "checkin", "result": result.model_dump(mode="json")},
    )


def _run_plan(session: Session, provider_for: ProviderFor) -> ChatMessage:
    try:
        plan = planning.generate_plan(session, provider_for)
    except NoAvailableNode:
        return _save(session, "assistant", "No node is ready yet. Make a world first.", "front_desk")
    except PlanFailed:
        session.rollback()
        return _save(session, "assistant", "I couldn't pick today's quests. Please try again.", "front_desk")
    titles = ", ".join(f"“{s.skill_title}”" for s in plan.steps)
    return _save(
        session,
        "assistant",
        f"Today's quests: {titles}.",
        "recommender",
        {"type": "plan", "plan": plan.model_dump(mode="json")},
    )


def _run_briefing(session: Session, provider_for: ProviderFor) -> ChatMessage:
    try:
        briefing = briefing_service.narrate(session, provider_for)
    except BriefingFailed:
        session.rollback()
        return _save(session, "assistant", "I couldn't put your status together. Please try again.", "front_desk")
    return _save(
        session,
        "assistant",
        briefing.narrative or "",
        "narrator",
        {"type": "briefing", "briefing": briefing.model_dump(mode="json")},
    )


# ---------------------------------------------------------------- the endpoint

def handle_message(
    session: Session,
    message: str,
    provider_for: ProviderFor,
    search_provider_for: Callable[[], SearchProvider],
    uploads: list[Upload] | None = None,
    course_topic: str | None = None,
) -> list[ChatMessageOut]:
    """`course_topic` (the tutorial) builds a course straight away: no front desk call, so the
    result does not hang on how the message would be classified."""
    user = _save(session, "user", message)  # kept even if the front desk fails

    if course_topic is not None:
        topic = course_topic.strip() or PurePath(uploads[0].filename).stem
        first = _save(session, "assistant", f"I'll build a world for “{topic}”.", "front_desk")
        syllabus = _syllabus_text(uploads) if uploads else None
        built = _run_generate_course(session, topic, provider_for, search_provider_for, syllabus)
        return [message_out(m) for m in (user, first, built)]

    nodes = _nodes_newest_course_first(session)
    try:
        routed: FrontDeskResult = FrontDesk(provider_for("front_desk")).route(message, [n.title for n in nodes])
    except Exception as exc:
        logger.warning("front desk failed", exc_info=True)
        session.rollback()
        raise FrontDeskUnavailable from exc

    content, action = routed.reply, None
    intent = routed.intent
    topic = str(routed.args.get("topic") or "").strip()

    if intent == "open_skill":
        node = resolve_node(nodes, str(routed.args.get("skill") or ""))
        if node is None:
            content = "Which node do you mean? Tell me its name."
        else:
            action = {"type": "navigate", "scene": "skill", "skill_id": node.id}
    elif intent == "open_map":
        action = {"type": "navigate", "scene": "map"}

    # Saved before the pipeline runs, so ids stay in reading order: user, front desk, result.
    first = _save(session, "assistant", content, "front_desk", action)
    result: list[ChatMessage] = [user, first]

    if uploads and intent in ("generate_course", "none"):
        # The file replaces the Syllabus Finder: the topic falls back to the first file's name.
        topic = topic or PurePath(uploads[0].filename).stem
        result.append(_run_generate_course(session, topic, provider_for, search_provider_for, _syllabus_text(uploads)))
    elif intent == "generate_course" and topic:
        result.append(_run_generate_course(session, topic, provider_for, search_provider_for))
    elif intent == "checkin":
        result.append(_run_checkin(session, message, provider_for))
    elif intent == "plan":
        result.append(_run_plan(session, provider_for))
    elif intent == "briefing":
        result.append(_run_briefing(session, provider_for))
    return [message_out(m) for m in result]


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
        items.append(ChatSuggestionOut(label="How was your day?", message="Let me log my day", skill_id=None))
    else:
        # Once the day is logged, item 1 is the current time window's reflection prompt (unless answered).
        prompt = journal.current_prompt(session)
        if prompt is not None:
            items.append(ChatSuggestionOut(label=prompt, message="", skill_id=None, reflection=True))

    # Continue the node of the most recent audit while it is not mastered ...
    last = session.exec(
        select(SkillNode)
        .join(AuditSession, AuditSession.skill_id == SkillNode.id)
        .order_by(col(AuditSession.created_at).desc(), col(AuditSession.id).desc())
    ).first()
    if last is not None and last.status != SkillStatus.mastered:
        label = f"Continue “{last.title}”"
        items.append(ChatSuggestionOut(label=label, message=label, skill_id=last.id))
        return items

    # ... otherwise start the newest course's lowest-id available node.
    course = session.exec(select(Course).order_by(col(Course.created_at).desc(), col(Course.id).desc())).first()
    node = None
    if course is not None:
        node = session.exec(
            select(SkillNode)
            .where(SkillNode.course_id == course.id, SkillNode.status == SkillStatus.available)
            .order_by(SkillNode.id)
        ).first()
    if node is not None:
        label = f"Start with “{node.title}”"
        items.append(ChatSuggestionOut(label=label, message=label, skill_id=node.id))
    else:
        # No course (or nothing left to open): the client only focuses the input.
        items.append(ChatSuggestionOut(label="Tell me what you want to learn", message="", skill_id=None))
    return items
