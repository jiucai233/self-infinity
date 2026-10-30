"""Putting the player's courses into the language the app is now in (POST /api/courses/translate).

A course is written in the language of the request that generated it. When the player switches
the app's language, every course not already in the new one is translated: the course title (the
first line of its topic; the clarification answers below it are the player's own words and stay),
each node's title and description, and each leaf's knowledge point titles. One Translator call
per course; a failed or incomplete answer leaves that course exactly as it was.

Audit transcripts, evidence, gap notes and anything else the player wrote are not touched. The
points of a node with an audit running are not touched either: the running audit matches its
results to them by title (app/services/points.py record_results).
"""

import logging
from dataclasses import dataclass

from sqlmodel import Session, col, select

from app.agents.translator import Translator
from app.i18n import language_of, use_language
from app.llm.base import LLMProvider
from app.models import AuditSession, AuditStatus, Course, SkillNode
from app.services import points as points_service
from app.services.courses import live_courses

logger = logging.getLogger(__name__)


@dataclass
class TranslationResult:
    translated: int = 0
    skipped: int = 0


def _title(course: Course) -> str:
    first = course.topic.split("\n")[0].strip()
    return first or course.topic.strip()


def _with_title(topic: str, title: str) -> str:
    first, sep, rest = topic.partition("\n")
    return f"{title}{sep}{rest}" if first.strip() else title


def _detected_language(course: Course, nodes: list[SkillNode]) -> str | None:
    text = "\n".join([_title(course), *(f"{n.title}\n{n.description}" for n in nodes)])
    return language_of(text)


def translate_courses(session: Session, provider: LLMProvider, language: str) -> TranslationResult:
    result = TranslationResult()
    courses = session.exec(live_courses().order_by(col(Course.id))).all()
    for course in courses:
        if course.language == language:
            continue
        nodes = session.exec(
            select(SkillNode).where(SkillNode.course_id == course.id).order_by(col(SkillNode.id))
        ).all()
        if course.language is None and _detected_language(course, nodes) == language:
            # Generated in this language and never translated: nothing to do but remember it.
            course.language = language
            session.add(course)
            session.commit()
            continue
        if _translate_course(session, provider, language, course, nodes):
            result.translated += 1
        else:
            result.skipped += 1
    return result


def _translate_course(
    session: Session, provider: LLMProvider, language: str, course: Course, nodes: list[SkillNode]
) -> bool:
    auditing = set(
        session.exec(
            select(AuditSession.skill_id).where(
                col(AuditSession.skill_id).in_([n.id for n in nodes]),
                AuditSession.status == AuditStatus.active,
            )
        ).all()
    ) if nodes else set()
    payload: dict = {"course": {"title": _title(course)}, "nodes": {}}
    for node in nodes:
        entry = {"title": node.title, "description": node.description}
        if node.points and node.id not in auditing:
            entry["points"] = [p["title"] for p in node.points]
        payload["nodes"][str(node.id)] = entry
    try:
        # The provider appends the request's language instruction; this call's language is the target.
        with use_language(language):
            translated = Translator(provider).translate(language, payload)
    except Exception:
        logger.warning("translating course %s failed, left as it was", course.id, exc_info=True)
        return False

    course.topic = _with_title(course.topic, translated["course"]["title"])
    course.language = language
    session.add(course)
    for node in nodes:
        entry = translated["nodes"][str(node.id)]
        node.title = entry["title"]
        node.description = entry["description"]
        if "points" in entry:
            kept = node.points
            for point, title in zip(kept, entry["points"]):
                point["title"] = title
            node.points_json = points_service.dump(kept)
        session.add(node)
    session.commit()
    return True
