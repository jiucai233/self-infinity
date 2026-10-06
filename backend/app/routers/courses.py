from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session, col, select

from app.db import get_session
from app.models import Course
from app.schemas import CourseGraphOut, CourseOut, SkillEdgeOut, SkillNodeOut
from app.services.tree import course_graph

router = APIRouter(prefix="/api/courses", tags=["courses"])


@router.get("", response_model=list[CourseOut])
def list_courses(session: Session = Depends(get_session)):
    """Newest first."""
    return session.exec(select(Course).order_by(col(Course.created_at).desc(), col(Course.id).desc())).all()


@router.get("/{course_id}/map", response_model=CourseGraphOut)
def get_course_map(course_id: int, session: Session = Depends(get_session)):
    course = session.get(Course, course_id)
    if course is None:
        raise HTTPException(404, "course not found")
    nodes, edges = course_graph(session, course.id)
    return CourseGraphOut(
        course=CourseOut.model_validate(course),
        nodes=[SkillNodeOut.model_validate(n) for n in nodes],
        edges=[SkillEdgeOut.model_validate(e) for e in edges],
    )
