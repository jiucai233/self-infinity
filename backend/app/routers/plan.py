"""POST /api/plan/generate and GET /api/plan/current (contract #15, #16)."""

from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session

from app.db import get_session
from app.llm import get_provider
from app.schemas import StudyPlanOut
from app.services import planning
from app.services.planning import NoAvailableNode, PlanFailed

router = APIRouter(prefix="/api/plan", tags=["plan"])


@router.get("/current", response_model=StudyPlanOut | None)
def get_current_plan(session: Session = Depends(get_session)):
    plan = planning.current_plan(session)
    return planning.plan_out(plan) if plan else None


@router.post("/generate", response_model=StudyPlanOut)
def generate_plan(session: Session = Depends(get_session)):
    try:
        return planning.generate_plan(session, lambda agent: get_provider(agent))
    except NoAvailableNode:
        raise HTTPException(400, "No node is available yet. Generate a course or pass an existing node first.")
    except PlanFailed:
        raise HTTPException(502, "Plan generation failed. Please try again.")
