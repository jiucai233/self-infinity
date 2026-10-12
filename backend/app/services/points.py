"""The knowledge points inside a leaf, and what an audit does with them.

A leaf is the smallest node; what is below it is not more nodes but its knowledge points
(`SkillNode.points_json`). An audit of the leaf examines the points still open, one by one, and
writes each one's result back, so the next audit starts from what was missed instead of from
the beginning. A leaf that has points is not broken down any further.

Points only count on a concept leaf: a node that gets parts keeps the column, and nothing reads it.
"""

import json
import logging

from sqlmodel import Session

from app.agents.point_lister import PointLister, clean_points
from app.llm.base import LLMProvider
from app.models import Course, NodePosition, NodeType, SkillNode, SkillStatus
from app.services.tree import node_position

logger = logging.getLogger(__name__)


def has_points(session: Session, skill: SkillNode) -> bool:
    """A concept leaf with knowledge points: the smallest node, audited point by point."""
    return (
        bool(skill.points)
        and skill.node_type == NodeType.concept
        and node_position(session, skill) == NodePosition.leaf
    )


def dump(points: list[dict]) -> str:
    return json.dumps(
        [{"title": p["title"], "ok": p.get("ok"), "note": p.get("note") or None} for p in points],
        ensure_ascii=False,
    )


def set_points(skill: SkillNode, titles: list[str]) -> None:
    """Gives the node these points, none asked yet; an empty list leaves it without."""
    titles = clean_points(titles)
    skill.points_json = dump([{"title": t, "ok": None} for t in titles]) if titles else None


def ensure_points(session: Session, skill: SkillNode, provider: LLMProvider) -> None:
    """Lists the points of a concept leaf that has none (an older course, a node added by hand).
    One LLM call, once per node; a failure leaves the node as it is."""
    if skill.points or skill.node_type != NodeType.concept or skill.unexpanded:
        return
    if node_position(session, skill) != NodePosition.leaf:
        return
    course = session.get(Course, skill.course_id)
    try:
        titles = PointLister(provider).list(
            (course.topic.splitlines()[0] if course and course.topic else skill.title),
            skill.title,
            skill.description,
        )
    except Exception:
        logger.warning("point lister failed, auditing without points", exc_info=True)
        return
    if titles:
        set_points(skill, titles)
        session.add(skill)
        session.commit()
        session.refresh(skill)


def to_examine(skill: SkillNode) -> list[dict]:
    """The points an audit starting now asks about, each with the note of its last miss: the
    ones not explained right yet. A node already mastered (a review) and a node with nothing
    left open get all of them again."""
    points = skill.points
    still_open = [p for p in points if p["ok"] is not True]
    if skill.status == SkillStatus.mastered or not still_open:
        still_open = points
    return [{"title": p["title"], "ok": None, "note": p["note"]} for p in still_open]


def record_results(skill: SkillNode, results: list[dict]) -> None:
    """Writes an audit's point results onto the node: what held, what was missed and why. A
    point the audit did not settle (null) keeps what it had."""
    settled = {r["title"]: r for r in results if r.get("ok") is not None}
    points = skill.points
    for point in points:
        result = settled.get(point["title"])
        if result is not None:
            point["ok"] = result["ok"]
            point["note"] = None if result["ok"] else (result.get("note") or point["note"])
    skill.points_json = dump(points) if points else None
