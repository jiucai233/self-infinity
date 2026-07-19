from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session, select

from app.agents.architect import Architect, GeneratedNode
from app.agents.clarifier import Clarifier
from app.db import get_session
from app.llm import get_provider
from app.models import SkillNode, SkillStatus
from app.schemas import ClarifyRequest, ClarifyResponse, GenerateTreeRequest, SkillNodeOut
from app.utils import slugify

router = APIRouter(prefix="/api/skills", tags=["skills"])


@router.get("", response_model=list[SkillNodeOut])
def list_skills(session: Session = Depends(get_session)):
    return session.exec(select(SkillNode)).all()


@router.post("/clarify", response_model=ClarifyResponse)
def clarify_topic(body: ClarifyRequest):
    clarifier = Clarifier(get_provider())
    try:
        result = clarifier.clarify(body.topic)
    except Exception:
        raise HTTPException(502, "澄清问题生成失败，请稍后重试")
    return ClarifyResponse(needs_clarification=result.needs_clarification, questions=result.questions)


@router.post("/generate", response_model=list[SkillNodeOut])
def generate_tree(body: GenerateTreeRequest, session: Session = Depends(get_session)):
    architect = Architect(get_provider())
    try:
        nodes = architect.generate(body.topic)
    except Exception:
        raise HTTPException(502, "技能树规划失败，请稍后重试")

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
        created.append(row)

    session.commit()
    for row in created:
        session.refresh(row)
    return created
