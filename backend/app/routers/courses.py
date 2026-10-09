import logging

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlmodel import Session, col

from app.db import get_session
from app.llm import get_provider
from app.models import Course
from app.schemas import CourseGraphOut, CourseOut, CourseSyllabusIn, SkillEdgeOut, SkillNodeOut
from app.search import get_search_provider
from app.services import course_generation
from app.services.chat import UploadNotFound, load_uploads, syllabus_text
from app.services.course_edit import course_root
from app.services.courses import CourseNotFound, delete_course, get_live_course, live_courses
from app.services.tree import course_graph

logger = logging.getLogger(__name__)

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


@router.post("/{course_id}/syllabus", response_model=CourseGraphOut)
def apply_syllabus(course_id: int, body: CourseSyllabusIn, session: Session = Depends(get_session)):
    """Adds what a syllabus covers and the course lacks, under the nodes it belongs to; nothing
    is removed or renamed. The syllabus is the uploaded files (`upload_ids`), or with none a
    syllabus searched for the course's subject (404 when none is found). Answers the course map."""
    course = get_live_course(session, course_id)
    if course is None:
        raise HTTPException(404, "course not found")
    try:
        uploads = load_uploads(session, body.upload_ids)
    except UploadNotFound:
        raise HTTPException(404, "upload not found") from None
    text, syllabus = None, None
    if uploads:
        text = syllabus_text(uploads)
    else:
        root = course_root(session, course.id)
        subject = root.title if root else course.topic.splitlines()[0]
        syllabus = course_generation.find_syllabus(
            subject, get_provider("syllabus_finder"), get_search_provider()
        )
        if syllabus is None:
            raise HTTPException(404, "No syllabus found for this course.")
    try:
        revised = course_generation.revise_course(
            session, course, get_provider("planner"), syllabus=syllabus, syllabus_text=text
        )
    except course_generation.CourseFull:
        raise HTTPException(409, "This course has reached its size limit.") from None
    except course_generation.CourseGenerationError:
        logger.warning("revising a course failed", exc_info=True)
        raise HTTPException(502, "Updating the course failed. Please try again.") from None
    return CourseGraphOut(
        course=CourseOut.model_validate(revised.course),
        nodes=[SkillNodeOut.model_validate(n) for n in revised.nodes],
        edges=[SkillEdgeOut.model_validate(e) for e in revised.edges],
    )
