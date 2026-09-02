from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session, select

import json
import logging

from app.agents.clarifier import Clarifier
from app.agents.planner import GeneratedNode, Planner
from app.agents.searcher import Searcher
from app.db import get_session
from app.llm import get_provider
from app.models import Principle, SearchPlan, SkillNode, SkillPrerequisite, SkillStatus
from app.schemas import (
    ClarifyRequest,
    ClarifyResponse,
    GenerateTreeRequest,
    GenerateTreeResponse,
    RecommendationOut,
    SearchPlanItemOut,
    SearchPlanOut,
    SearchPlanRequest,
    SkillNodeOut,
    SkillPrerequisiteOut,
)
from app.search import get_search_provider
from app.services import bandit
from app.services.prerequisites import add_prerequisites
from app.utils import slugify

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/skills", tags=["skills"])


@router.get("", response_model=list[SkillNodeOut])
def list_skills(session: Session = Depends(get_session)):
    return session.exec(select(SkillNode)).all()


@router.get("/recommendation", response_model=RecommendationOut)
def get_recommendation(session: Session = Depends(get_session)):
    """V2.1 contextual bandit (whitepaper §4.4): which difficulty tier the
    user's recent audit history suggests they're ready for right now, plus
    each available node's tier so the frontend can highlight matches. Every
    call re-samples the bandit's posterior (Thompson Sampling), so repeated
    calls can legitimately return different tiers — that's exploration
    working as intended, not flicker to be "fixed" with caching."""
    bucket = bandit.context_bucket(session)
    tier = bandit.choose_tier(session, bucket)
    available = session.exec(select(SkillNode).where(SkillNode.status == SkillStatus.available)).all()
    tiers = {s.id: bandit.difficulty_tier(session, s) for s in available}
    session.commit()
    return RecommendationOut(context_bucket=bucket, suggested_tier=tier, skill_tiers=tiers)


@router.post("/clarify", response_model=ClarifyResponse)
def clarify_topic(body: ClarifyRequest):
    clarifier = Clarifier(get_provider())
    try:
        result = clarifier.clarify(body.topic)
    except Exception:
        raise HTTPException(502, "澄清问题生成失败，请稍后重试")
    return ClarifyResponse(needs_clarification=result.needs_clarification, questions=result.questions)


@router.post("/generate", response_model=GenerateTreeResponse)
def generate_tree(body: GenerateTreeRequest, session: Session = Depends(get_session)):
    """编排一门课：节点 + 分类树 + 先修边。

    先修边和 parent_id 长在同一批节点上但含义不同（分类 vs 顺序），成环的边会在
    落库时被丢弃——见 app/services/prerequisites.py。
    """
    planner = Planner(get_provider())
    try:
        course = planner.generate(
            body.topic,
            node_count=body.node_count,
            max_depth=body.max_depth,
            difficulty=body.difficulty,
        )
    except Exception:
        raise HTTPException(502, "课程编排失败，请稍后重试")
    nodes = course.nodes

    taken_slugs = set(session.exec(select(SkillNode.slug)).all())

    def unique_slug(base: str) -> str:
        candidate = base or "node"
        if candidate not in taken_slugs:
            taken_slugs.add(candidate)
            return candidate
        i = 2
        while f"{candidate}-{i}" in taken_slugs:
            i += 1
        final = f"{candidate}-{i}"
        taken_slugs.add(final)
        return final

    # 生成节点的 parent_slug 引用的是本批次内的原始 slug，需要先落库拿到真实 id
    # 再解析子节点，父节点未落库前子节点必须等待——用重复扫描直到全部解决。
    pending: list[GeneratedNode] = list(nodes)
    original_to_id: dict[str, int] = {}
    created: list[SkillNode] = []

    max_passes = len(pending) + 1
    for _ in range(max_passes):
        if not pending:
            break
        still_pending: list[GeneratedNode] = []
        for node in pending:
            parent_resolved = node.parent_slug is None or node.parent_slug in original_to_id
            if not parent_resolved:
                still_pending.append(node)
                continue

            parent_id = original_to_id.get(node.parent_slug) if node.parent_slug else None
            status = SkillStatus.available if parent_id is None else SkillStatus.locked
            row = SkillNode(
                slug=unique_slug(slugify(node.title)),
                title=node.title,
                description=node.description,
                parent_id=parent_id,
                status=status,
                node_type=node.node_type,
            )
            session.add(row)
            session.flush()
            original_to_id[node.slug] = row.id
            created.append(row)
        pending = still_pending

    # 剩下没能解析父节点的（LLM 输出了不存在的 parent_slug），一律挂到根节点下。
    root_id = created[0].id if created else None
    for node in pending:
        row = SkillNode(
            slug=unique_slug(slugify(node.title)),
            title=node.title,
            description=node.description,
            parent_id=root_id,
            status=SkillStatus.locked,
            node_type=node.node_type,
        )
        session.add(row)
        session.flush()
        # 这些节点的 parent_slug 解析失败被挂到了根下，但它们仍然可以是先修边的
        # 端点——不登记就会让本来有效的先修边因为查不到 id 而被丢掉。
        original_to_id[node.slug] = row.id
        created.append(row)

    # 丢弃与父子关系重合的先修边。它们不是错的，只是冗余：解锁机制本来就规定了
    # 父节点通过之后子节点才 available，父子顺序已经被强制。prompt 里明确要求过
    # "不要把父子边抄一遍"，但模型仍会产出，所以这里兜一道。
    parent_of = {n.slug: n.parent_slug for n in course.nodes}
    edges = [
        (original_to_id[p.to_slug], original_to_id[p.from_slug], p.reason)
        for p in course.prerequisites
        if p.to_slug in original_to_id
        and p.from_slug in original_to_id
        and parent_of.get(p.to_slug) != p.from_slug
    ]
    add_prerequisites(session, edges)

    session.commit()
    for row in created:
        session.refresh(row)

    created_ids = {row.id for row in created}
    stored_edges = [
        e
        for e in session.exec(select(SkillPrerequisite)).all()
        if e.skill_id in created_ids or e.prerequisite_id in created_ids
    ]
    return GenerateTreeResponse(
        # response_model 不再是 list[SkillNodeOut]，手动构造响应时 pydantic 不会
        # 再替我们把 ORM 行转过去，必须显式转换。
        nodes=[SkillNodeOut.model_validate(row, from_attributes=True) for row in created],
        prerequisites=[
            SkillPrerequisiteOut(
                skill_id=e.skill_id, prerequisite_id=e.prerequisite_id, reason=e.reason
            )
            for e in stored_edges
        ],
    )


@router.post("/{skill_id}/search-plan", response_model=SearchPlanOut)
def create_search_plan(
    skill_id: int, body: SearchPlanRequest, session: Session = Depends(get_session)
):
    """为一个具体缺口检索补救材料。

    强制要求 gap 或 misconception_id：检索是验证失败之后的补救动作，不是一个泛用的
    资料搜索入口（见 app/agents/searcher.py 的模块注释）。缺了上下文直接 400，
    而不是friendly 地退化成主题搜索——那个退化正是要防的东西。
    """
    skill = session.get(SkillNode, skill_id)
    if skill is None:
        raise HTTPException(404, "skill not found")

    gap = (body.gap or "").strip()
    if not gap and body.misconception_id is not None:
        principle = session.get(Principle, body.misconception_id)
        if principle is None or not principle.misconception:
            raise HTTPException(404, "principle not found or has no misconception")
        gap = principle.misconception
    if not gap:
        raise HTTPException(400, "必须提供 gap 或 misconception_id —— 检索只针对具体缺口")

    searcher = Searcher(get_provider(), get_search_provider())
    try:
        queries, items = searcher.plan(skill.title, skill.description, gap)
    except Exception:
        logger.warning("search plan failed", exc_info=True)
        raise HTTPException(502, "资料检索失败，请稍后重试")

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

    return SearchPlanOut(
        id=plan.id,
        skill_id=plan.skill_id,
        gap=plan.gap,
        queries=queries,
        items=[SearchPlanItemOut(title=i.title, url=i.url, snippet=i.snippet, reason=i.reason) for i in items],
        created_at=plan.created_at,
    )
