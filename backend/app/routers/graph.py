from fastapi import APIRouter, Depends
from sqlmodel import Session, select

from app.db import get_session
from app.services.courses import live_nodes
from app.models import AuditSession, LinkTargetKind, Principle, PrincipleLink, SkillEdge, SkillNode
from app.schemas import GraphEdgeOut, GraphNodeOut, GraphResponse

router = APIRouter(prefix="/api", tags=["graph"])


@router.get("/graph", response_model=GraphResponse)
def get_graph(session: Session = Depends(get_session)):
    """技能节点和教训（principle）节点放在同一张图里。全部来自已有数据，没有凭空生成的东西。

    节点 id 是 "skill:<id>" / "principle:<id>"。五种边（方向都写在契约里）：

    - contains：父 → 子，真实的课程结构（SkillEdge）。
    - requires：先学 → 后学（SkillEdge）。两种边长在同一批节点上却表达不同的东西：contains
      是分类，requires 是顺序，所以前端才能分开画。
    - origin：教训 → 它产生于的那个节点（Principle → 来源审计 → 节点）。
    - related：教训 → 教训或节点；contradicts：教训 → 教训。这两种是 Linker 判断后
      存下来的 PrincipleLink，读取时不会触发任何 LLM 调用。
    """
    # A course deleted keeping its nodes is hidden: its nodes and every edge to them leave the
    # graph, its lesson cards stay.
    skills = session.exec(live_nodes().order_by(SkillNode.id)).all()
    shown = {s.id for s in skills}
    principles = session.exec(select(Principle).order_by(Principle.id)).all()
    origin_of = dict(
        session.exec(
            select(Principle.id, AuditSession.skill_id).join(AuditSession, AuditSession.id == Principle.source_session_id)
        ).all()
    )

    nodes = [
        GraphNodeOut(
            id=f"skill:{s.id}",
            kind="skill",
            title=s.title,
            status=s.status,
            node_type=s.node_type,
            course_id=s.course_id,
        )
        for s in skills
    ] + [GraphNodeOut(id=f"principle:{p.id}", kind="principle", title=p.title) for p in principles]

    edges = [
        GraphEdgeOut(
            source=f"skill:{e.from_id}",
            target=f"skill:{e.to_id}",
            kind=e.kind.value,
            reason=e.reason if e.kind.value == "requires" else None,
        )
        for e in session.exec(select(SkillEdge).order_by(SkillEdge.id)).all()
        if e.from_id in shown and e.to_id in shown
    ]

    for p in principles:
        if origin_of.get(p.id) in shown:
            edges.append(GraphEdgeOut(source=f"principle:{p.id}", target=f"skill:{origin_of[p.id]}", kind="origin"))

    for link in session.exec(select(PrincipleLink).order_by(PrincipleLink.id)).all():
        target_kind = "skill" if link.target_kind == LinkTargetKind.skill else "principle"
        if target_kind == "skill" and link.target_id not in shown:
            continue
        edges.append(
            GraphEdgeOut(
                source=f"principle:{link.principle_id}",
                target=f"{target_kind}:{link.target_id}",
                kind=link.kind.value,
                reason=link.reason or None,
            )
        )

    return GraphResponse(nodes=nodes, edges=edges)
