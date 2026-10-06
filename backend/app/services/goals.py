"""Main quests: one-year goals with courses under them (contract section 6, endpoints 28-31). No LLM."""

import json

from fastapi import HTTPException
from sqlmodel import Session, col, select

from app.models import Course, Goal
from app.schemas import GOALS_MAX, GoalCreate, GoalOut, GoalUpdate


def _out(goal: Goal) -> GoalOut:
    return GoalOut(id=goal.id, title=goal.title, course_ids=json.loads(goal.course_ids_json), created_at=goal.created_at)


def _all(session: Session) -> list[Goal]:
    return list(session.exec(select(Goal).order_by(col(Goal.created_at), col(Goal.id))).all())


def list_goals(session: Session) -> list[GoalOut]:
    """Oldest first: the first goal is the one the player set first."""
    return [_out(g) for g in _all(session)]


def create_goal(session: Session, body: GoalCreate) -> GoalOut:
    if len(_all(session)) >= GOALS_MAX:
        raise HTTPException(409, f"at most {GOALS_MAX} main quests")
    goal = Goal(title=body.title)
    session.add(goal)
    session.commit()
    session.refresh(goal)
    return _out(goal)


def update_goal(session: Session, goal_id: int, body: GoalUpdate) -> GoalOut:
    goal = session.get(Goal, goal_id)
    if goal is None:
        raise HTTPException(404, "goal not found")
    if "title" in body.model_fields_set:
        goal.title = body.title
    if "course_ids" in body.model_fields_set:
        for course_id in body.course_ids:
            if session.get(Course, course_id) is None:
                raise HTTPException(404, "course not found")
        # A course belongs to one goal at most: attaching it here detaches it everywhere else.
        moved = set(body.course_ids)
        for other in _all(session):
            if other.id == goal.id:
                continue
            kept = [c for c in json.loads(other.course_ids_json) if c not in moved]
            if len(kept) != len(json.loads(other.course_ids_json)):
                other.course_ids_json = json.dumps(kept)
                session.add(other)
        goal.course_ids_json = json.dumps(body.course_ids)
    session.add(goal)
    session.commit()
    session.refresh(goal)
    return _out(goal)


def delete_goal(session: Session, goal_id: int) -> None:
    goal = session.get(Goal, goal_id)
    if goal is None:
        raise HTTPException(404, "goal not found")
    session.delete(goal)
    session.commit()
