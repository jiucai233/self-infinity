"""Main quests (contract #28-#31). No LLM."""

from fastapi import APIRouter, Depends, Response
from sqlmodel import Session

from app.db import get_session
from app.schemas import GoalCreate, GoalOut, GoalUpdate
from app.services import goals

router = APIRouter(prefix="/api", tags=["goals"])


@router.get("/goals", response_model=list[GoalOut])
def list_goals(session: Session = Depends(get_session)):
    return goals.list_goals(session)


@router.post("/goals", response_model=GoalOut)
def create_goal(body: GoalCreate, session: Session = Depends(get_session)):
    return goals.create_goal(session, body)


@router.put("/goals/{goal_id}", response_model=GoalOut)
def update_goal(goal_id: int, body: GoalUpdate, session: Session = Depends(get_session)):
    return goals.update_goal(session, goal_id, body)


@router.delete("/goals/{goal_id}", status_code=204)
def delete_goal(goal_id: int, session: Session = Depends(get_session)):
    goals.delete_goal(session, goal_id)
    return Response(status_code=204)
