from fastapi import APIRouter, Depends, HTTPException, Query
from sqlmodel import Session, col

from app.db import get_session
from app.models import Course
from app.schemas import CourseGraphOut, CourseOut, SkillEdgeOut, SkillNodeOut
from app.services.courses import CourseNotFound, delete_course, get_live_course, live_courses
from app.services.tree import course_graph

router = APIRouter(prefix="/api/courses", tags=["courses"])


@router.get("", response_model=list[CourseOut])
def list_courses(session: Session = Depends(get_session)):
    """Newest first."""
    return session.exec(live_courses().order_by(col(Course.created_at).desc(), col(Course.id).desc())).all()


@router.get("/{course_id}/map", response_model=CourseGraphOut)
def get_course_map(course_id: int, session: Session = Depends(get_session)):
    course = get_live_course(session, course_id)
    if course is None:
        raise HTTPException(404, "course not found")
    nodes, edges = course_graph(session, course.id)
    return CourseGraphOut(
        course=CourseOut.model_validate(course),
        nodes=[SkillNodeOut.model_validate(n) for n in nodes],
        edges=[SkillEdgeOut.model_validate(e) for e in edges],
    )


@router.delete("/{course_id}", status_code=204)
def remove_course(
    course_id: int,
    delete_nodes: bool = Query(False),
    session: Session = Depends(get_session),
):
    """Deletes a course. `delete_nodes=false` keeps its nodes, audits and lesson cards (hidden with
    the course); `true` deletes them too. 404 for an unknown or already deleted course."""
    try:
        delete_course(session, course_id, delete_nodes=delete_nodes)
    except CourseNotFound:
        raise HTTPException(404, "course not found") from None
