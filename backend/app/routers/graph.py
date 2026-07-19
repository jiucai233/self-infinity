from fastapi import APIRouter, Depends
from sqlmodel import Session, select

from app.agents.retrieval import relevance_score
from app.db import get_session
from app.models import AuditSession, Principle, SkillNode
from app.schemas import GraphEdgeOut, GraphNodeOut, GraphResponse

router = APIRouter(prefix="/api", tags=["graph"])

# Cap on extra "related" edges per principle beyond its real origin edge —
# without a cap a handful of generic-sounding principles would fan out to
# every skill node and turn the graph into an unreadable hairball.
MAX_RELATED_EDGES_PER_PRINCIPLE = 2


@router.get("/graph", response_model=GraphResponse)
def get_graph(session: Session = Depends(get_session)):
    """Unified skill-tree + principle-archive graph.

    Three edge kinds, all derived from data that already exists — nothing
    fabricated:
    - "parent": the real skill-tree structure (SkillNode.parent_id).
    - "origin": a principle's real source (Principle.source_session_id ->
      AuditSession.skill_id) — the node whose failed audit produced it.
    - "related": a principle to any OTHER skill node scored above zero by
      the same character-bigram/word-overlap heuristic
      app/agents/retrieval.py already uses for in-audit principle
      retrieval, capped at MAX_RELATED_EDGES_PER_PRINCIPLE per principle.
    """
    skills = session.exec(select(SkillNode)).all()
    principles = session.exec(select(Principle)).all()
    sessions_by_id = {s.id: s for s in session.exec(select(AuditSession)).all()}

    nodes: list[GraphNodeOut] = [
        GraphNodeOut(
            id=f"skill-{s.id}",
            kind="skill",
            title=s.title,
            status=s.status,
            node_type=s.node_type,
        )
        for s in skills
    ]
    nodes += [
        GraphNodeOut(id=f"principle-{p.id}", kind="principle", title=p.title) for p in principles
    ]

    edges: list[GraphEdgeOut] = [
        GraphEdgeOut(source=f"skill-{s.parent_id}", target=f"skill-{s.id}", kind="parent")
        for s in skills
        if s.parent_id is not None
    ]

    for p in principles:
        origin_audit = sessions_by_id.get(p.source_session_id)
        origin_skill_id = origin_audit.skill_id if origin_audit is not None else None
        if origin_skill_id is not None:
            edges.append(
                GraphEdgeOut(
                    source=f"principle-{p.id}",
                    target=f"skill-{origin_skill_id}",
                    kind="origin",
                )
            )

        principle_text = f"{p.title} {p.body}"
        scored = [
            (s, relevance_score(principle_text, f"{s.title} {s.description}"))
            for s in skills
            if s.id != origin_skill_id
        ]
        scored = [(s, score) for s, score in scored if score > 0]
        scored.sort(key=lambda item: item[1], reverse=True)
        for s, _score in scored[:MAX_RELATED_EDGES_PER_PRINCIPLE]:
            edges.append(
                GraphEdgeOut(source=f"principle-{p.id}", target=f"skill-{s.id}", kind="related")
            )

    return GraphResponse(nodes=nodes, edges=edges)
