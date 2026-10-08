import json
import logging

from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session, col, select

from app.agents.clarifier import Clarifier, ClarifyResult
from app.agents.course_scout import CourseScout, PlayerContext
from app.agents.material_finder import MaterialFinder
from app.db import get_session
from app.llm import get_provider
from app.models import AuditSession, Course, EdgeKind, Goal, Principle, Profile, SearchPlan, SkillEdge, SkillNode
from app.routers.audits import audit_summary
from app.schemas import (
    ClarifyRequest,
    ClarifyResponse,
    CourseGraphOut,
    CourseOut,
    GenerateCourseRequest,
    RecommendationOut,
    RequiredSkillOut,
    ScoutOptionOut,
    ScoutRequest,
    ScoutResponse,
    SearchPlanItemOut,
    SearchPlanOut,
    SearchPlanRequest,
    SkillEdgeOut,
    SkillNodeOut,
    SkillOverviewOut,
)
from app.search import get_search_provider
from app.services import bandit, course_generation
from app.services.course_generation import CourseFull, CourseGenerationError, NotExpandable
from app.services.courses import live_nodes
from app.services.tree import contains_parents, depth_map

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/skills", tags=["skills"])


def search_plan_out(plan: SearchPlan) -> SearchPlanOut:
    return SearchPlanOut(
        id=plan.id,
        skill_id=plan.skill_id,
        gap=plan.gap,
        queries=json.loads(plan.queries_json),
        items=[SearchPlanItemOut(**item) for item in json.loads(plan.items_json)],
        created_at=plan.created_at,
    )


@router.get("", response_model=list[SkillNodeOut])
def list_skills(course_id: int | None = None, session: Session = Depends(get_session)):
    """Nodes ordered by id; all courses unless `course_id` narrows it."""
    query = live_nodes().order_by(SkillNode.id)
    if course_id is not None:
        query = query.where(SkillNode.course_id == course_id)
    return session.exec(query).all()


@router.get("/recommendation", response_model=RecommendationOut)
def get_recommendation(session: Session = Depends(get_session)):
    """Which difficulty tier the user's recent audit history suggests they're ready for
    right now (contextual bandit, see app/services/bandit.py), plus every node's tier so
    the client can highlight matches. Every call re-samples the bandit's posterior
    (Thompson Sampling), so repeated calls can legitimately return different tiers —
    that's exploration working as intended, not flicker to be "fixed" with caching.
    """
    bucket = bandit.context_bucket(session)
    tier = bandit.choose_tier(session, bucket)
    depths = depth_map(session)
    nodes = session.exec(live_nodes().order_by(SkillNode.id)).all()
    tiers = {n.id: bandit.difficulty_tier(session, n, depths.get(n.id, 0)) for n in nodes}
    session.commit()  # choose_tier may have created bandit arms
    return RecommendationOut(context_bucket=bucket, suggested_tier=tier, skill_tiers=tiers)


@router.post("/clarify", response_model=ClarifyResponse)
def clarify_topic(body: ClarifyRequest):
    # Clarifier 失败不是错误：当作"不需要澄清"，用户直接进入生成。
    try:
        result = Clarifier(get_provider("clarifier")).clarify(body.topic)
    except Exception:
        logger.warning("clarifier could not run, skipping clarification", exc_info=True)
        result = ClarifyResult(needs_clarification=False, questions=[])
    return ClarifyResponse(needs_clarification=result.needs_clarification, questions=result.questions)


@router.post("/scout", response_model=ScoutResponse)
def scout_course(body: ScoutRequest, session: Session = Depends(get_session)):
    """The tutorial's first course: reads the answer next to the player's main quests and profile.
    A clear answer comes back tidied; a vague one comes back as options to pick from. Never fails:
    a scout that cannot run answers `clear` with what was typed."""
    profile = session.get(Profile, 1) or Profile()
    quests = [g.title for g in session.exec(select(Goal).order_by(Goal.id)).all()]
    context = PlayerContext(
        main_quests=quests,
        win_condition=profile.vision,
        stakes=profile.anti_vision,
        identity=profile.identity,
    )
    result = CourseScout(get_provider("course_scout")).scout(body.answer, context)
    return ScoutResponse(
        kind=result.kind,
        topic=result.topic,
        question=result.question,
        options=[ScoutOptionOut(topic=o.topic, why=o.why) for o in result.options],
    )


@router.post("/generate", response_model=CourseGraphOut)
def generate_course(body: GenerateCourseRequest, session: Session = Depends(get_session)):
    """编排一门课：节点 + contains 边 + requires 边。

    Planner 的输出先过 Structure Validator 再落库，所以保存下来的课程一定满足 plan 8.3 的
    结构性质。只有根节点是 available。
    """
    try:
        generated = course_generation.generate_course(
            session,
            topic=body.topic,
            difficulty=body.difficulty,
            search_syllabus=body.search_syllabus,
            planner_provider=get_provider("planner"),
            syllabus_provider=get_provider("syllabus_finder"),
            search_provider=get_search_provider(),
        )
    except CourseGenerationError:
        logger.warning("course generation failed", exc_info=True)
        raise HTTPException(502, "Course generation failed. Please try again.")
    return CourseGraphOut(
        course=CourseOut.model_validate(generated.course),
        nodes=[SkillNodeOut.model_validate(n) for n in generated.nodes],
        edges=[SkillEdgeOut.model_validate(e) for e in generated.edges],
    )


@router.post("/{skill_id}/expand", response_model=CourseGraphOut)
def expand_skill(skill_id: int, session: Session = Depends(get_session)):
    """Breaks a node the Planner left as a category (`unexpanded`) down into its parts; answers
    the whole course map. Any node can be expanded, locked or not: looking inside is free."""
    skill = session.get(SkillNode, skill_id)
    if skill is None:
        raise HTTPException(404, "skill not found")
    try:
        expanded = course_generation.expand_node(session, skill, get_provider("planner"))
    except NotExpandable:
        raise HTTPException(400, "This node is already broken down.") from None
    except CourseFull:
        raise HTTPException(409, "This course has reached its size limit.") from None
    except CourseGenerationError:
        logger.warning("expanding a node failed", exc_info=True)
        raise HTTPException(502, "Breaking this node down failed. Please try again.") from None
    return CourseGraphOut(
        course=CourseOut.model_validate(expanded.course),
        nodes=[SkillNodeOut.model_validate(n) for n in expanded.nodes],
        edges=[SkillEdgeOut.model_validate(e) for e in expanded.edges],
    )


@router.post("/{skill_id}/search-plan", response_model=SearchPlanOut)
def create_search_plan(skill_id: int, body: SearchPlanRequest, session: Session = Depends(get_session)):
    """Material for one specific gap. A gap or a misconception id is required: search is a
    remedy after a failed audit, not a general material search."""
    gap = (body.gap or "").strip()
    if not gap and body.misconception_id is None:
        raise HTTPException(400, "A gap or misconception id is required. Search targets a specific gap only.")
    skill = session.get(SkillNode, skill_id)
    if skill is None:
        raise HTTPException(404, "skill not found")
    if not gap:
        principle = session.get(Principle, body.misconception_id)
        if principle is None or not (principle.misconception or "").strip():
            raise HTTPException(404, "misconception not found")
        gap = principle.misconception.strip()

    try:
        queries, items = MaterialFinder(get_provider("material_finder"), get_search_provider()).find(
            skill.title, skill.description, gap
        )
    except Exception:
        logger.warning("search plan failed", exc_info=True)
        raise HTTPException(502, "Material search failed. Please try again.")

    plan = SearchPlan(
        skill_id=skill.id,
        gap=gap,
        queries_json=json.dumps(queries, ensure_ascii=False),
        items_json=json.dumps(
            [{"title": i.title, "url": i.url, "snippet": i.snippet, "reason": i.reason} for i in items],
            ensure_ascii=False,
        ),
    )
    session.add(plan)
    session.commit()
    session.refresh(plan)
    return search_plan_out(plan)


@router.get("/{skill_id}/overview", response_model=SkillOverviewOut)
def get_overview(skill_id: int, session: Session = Depends(get_session)):
    """One node with its course, contains parents, required nodes, audits and materials (no LLM)."""
    skill = session.get(SkillNode, skill_id)
    if skill is None:
        raise HTTPException(404, "skill not found")
    course = session.get(Course, skill.course_id)

    required = session.exec(
        select(SkillEdge, SkillNode)
        .join(SkillNode, SkillNode.id == SkillEdge.from_id)
        .where(SkillEdge.to_id == skill.id, SkillEdge.kind == EdgeKind.requires)
        .order_by(SkillEdge.id)
    ).all()
    audits = session.exec(
        select(AuditSession)
        .where(AuditSession.skill_id == skill.id)
        .order_by(col(AuditSession.created_at).desc(), col(AuditSession.id).desc())
    ).all()
    plans = session.exec(
        select(SearchPlan)
        .where(SearchPlan.skill_id == skill.id)
        .order_by(col(SearchPlan.created_at).desc(), col(SearchPlan.id).desc())
    ).all()
    return SkillOverviewOut(
        skill=SkillNodeOut.model_validate(skill),
        course=CourseOut.model_validate(course),
        contains_parents=[SkillNodeOut.model_validate(p) for p in contains_parents(session, skill.id)],
        requires=[RequiredSkillOut(skill=SkillNodeOut.model_validate(n), reason=e.reason) for e, n in required],
        audits=[audit_summary(a, skill) for a in audits],
        materials=[search_plan_out(p) for p in plans],
    )
