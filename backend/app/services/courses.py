"""Deleting a course (contract endpoint 33), and the queries that leave deleted courses out.

Two ways to delete:

- **Keep the nodes** (the default): the course is archived. It leaves the course list, the
  maps, the life tree, the main quests, the chat and the plan, but its nodes, its audits and the
  lesson cards they produced stay in the database: the lessons still show and still link, and
  the audit history keeps its entries.
- **Delete the nodes**: the course and everything it produced go — nodes, edges, audits and
  their turns and rewards, the lesson cards those audits produced and every link to or from
  them, the nodes' search plans.

Either way the course leaves its main quest and the steps of any study plan.
"""

import json

from sqlmodel import Session, col, delete, or_, select

from app.models import (
    AuditSession,
    AuditTurn,
    Course,
    Goal,
    LinkTargetKind,
    Principle,
    PrincipleLink,
    RewardEvent,
    SearchPlan,
    SkillEdge,
    SkillNode,
    StudyPlan,
    utcnow,
)


class CourseNotFound(Exception):
    pass


def live_courses():
    """Courses that are not deleted."""
    return select(Course).where(col(Course.archived_at).is_(None))


def live_nodes():
    """Nodes of courses that are not deleted (a course deleted keeping its nodes hides them)."""
    return select(SkillNode).join(Course, Course.id == SkillNode.course_id).where(col(Course.archived_at).is_(None))


def live_node_ids(session: Session) -> set[int]:
    return set(session.exec(live_nodes().with_only_columns(SkillNode.id)).all())


def get_live_course(session: Session, course_id: int) -> Course | None:
    course = session.get(Course, course_id)
    return course if course is not None and course.archived_at is None else None


def delete_course(session: Session, course_id: int, *, delete_nodes: bool) -> None:
    course = get_live_course(session, course_id)
    if course is None:
        raise CourseNotFound

    for goal in session.exec(select(Goal)).all():
        ids = json.loads(goal.course_ids_json)
        if course_id in ids:
            goal.course_ids_json = json.dumps([c for c in ids if c != course_id])
            session.add(goal)
    for plan in session.exec(select(StudyPlan)).all():
        steps = json.loads(plan.steps_json)
        kept = [s for s in steps if s.get("course_id") != course_id]
        if len(kept) != len(steps):
            plan.steps_json = json.dumps(kept, ensure_ascii=False)
            session.add(plan)

    if not delete_nodes:
        course.archived_at = utcnow()
        session.add(course)
        session.commit()
        return

    nodes = list(session.exec(select(SkillNode.id).where(SkillNode.course_id == course_id)).all())
    audits = list(session.exec(select(AuditSession.id).where(col(AuditSession.skill_id).in_(nodes))).all())
    lessons = list(session.exec(select(Principle.id).where(col(Principle.source_session_id).in_(audits))).all())

    session.exec(
        delete(PrincipleLink).where(
            or_(
                col(PrincipleLink.principle_id).in_(lessons),
                (PrincipleLink.target_kind == LinkTargetKind.principle) & col(PrincipleLink.target_id).in_(lessons),
                (PrincipleLink.target_kind == LinkTargetKind.skill) & col(PrincipleLink.target_id).in_(nodes),
            )
        )
    )
    session.exec(delete(Principle).where(col(Principle.id).in_(lessons)))
    session.exec(delete(RewardEvent).where(col(RewardEvent.session_id).in_(audits)))
    session.exec(delete(AuditTurn).where(col(AuditTurn.session_id).in_(audits)))
    session.exec(delete(AuditSession).where(col(AuditSession.id).in_(audits)))
    session.exec(delete(SearchPlan).where(col(SearchPlan.skill_id).in_(nodes)))
    session.exec(delete(SkillEdge).where(or_(col(SkillEdge.from_id).in_(nodes), col(SkillEdge.to_id).in_(nodes))))
    session.exec(delete(SkillNode).where(col(SkillNode.id).in_(nodes)))
    session.delete(course)
    session.commit()
