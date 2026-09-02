from fastapi import APIRouter, Depends
from sqlmodel import Session, select

from app.db import get_session
from app.llm import get_provider
from app.models import AuditSession, LinkKind, Principle, PrincipleLink, SkillNode, SkillPrerequisite
from app.schemas import ContradictionOut, GraphEdgeOut, GraphNodeOut, GraphResponse, RelinkResponse
from app.services.linking import link_principle

router = APIRouter(prefix="/api", tags=["graph"])


@router.get("/graph", response_model=GraphResponse)
def get_graph(session: Session = Depends(get_session)):
    """Unified skill-tree + principle-archive graph.

    Five edge kinds, all derived from data that already exists — nothing
    fabricated:
    - "parent": the real skill-tree structure (SkillNode.parent_id) —
      classification, "is a kind of".
    - "prerequisite": SkillPrerequisite rows — ordering, "must know first".
      A second set of edges over the same nodes, and deliberately separate
      from "parent" because tree traversal order is not learning order:
      prerequisites routinely run between siblings and across branches,
      neither of which the tree can express. See app/agents/planner.py.
    - "origin": a principle's real source (Principle.source_session_id ->
      AuditSession.skill_id) — the node whose failed audit produced it.
    - "related" / "contradicts": persisted PrincipleLink rows, judged by the
      Librarian agent (an LLM call) rather than computed live here — see
      app/services/linking.py. A principle gets linked automatically when
      it's created; re-running the judgment for every principle (e.g. after
      changing the prompt, or to catch principles that predate this feature)
      is a manual action via POST /api/graph/relink, not something this
      read endpoint triggers itself.
    """
    skills = session.exec(select(SkillNode)).all()
    principles = session.exec(select(Principle)).all()
    sessions_by_id = {s.id: s for s in session.exec(select(AuditSession)).all()}
    links = session.exec(select(PrincipleLink)).all()
    prerequisites = session.exec(select(SkillPrerequisite)).all()

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

    # 方向和阅读顺序一致：从先修节点指向需要它的节点（"先学这个，再学那个"）。
    skill_ids = {s.id for s in skills}
    edges += [
        GraphEdgeOut(
            source=f"skill-{e.prerequisite_id}",
            target=f"skill-{e.skill_id}",
            kind="prerequisite",
            reason=e.reason or None,
        )
        for e in prerequisites
        # 指向已删除节点的边直接跳过，否则前端会渲染出一条断头的连线。
        if e.prerequisite_id in skill_ids and e.skill_id in skill_ids
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

    for link in links:
        edges.append(
            GraphEdgeOut(
                source=f"principle-{link.principle_id}",
                target=f"{link.target_kind.value}-{link.target_id}",
                kind=link.kind.value,
                reason=link.reason,
            )
        )

    return GraphResponse(nodes=nodes, edges=edges)


@router.post("/graph/relink", response_model=RelinkResponse)
def relink_graph(session: Session = Depends(get_session)):
    """Re-runs the Librarian for every principle against the full current
    library and skill tree, replacing all persisted PrincipleLink rows.

    This is the "linting pass": besides refreshing "related" edges (so
    principles created before this feature existed, or before the prompt
    changed, get judged too), it's the only place contradictions between
    principles get surfaced — a POST because it's a real (LLM-call-heavy,
    O(n) in principle count) recompute, not something to trigger implicitly
    on every graph read.
    """
    provider = get_provider()
    principles = session.exec(select(Principle)).all()
    sessions_by_id = {s.id: s for s in session.exec(select(AuditSession)).all()}

    for link in session.exec(select(PrincipleLink)).all():
        session.delete(link)
    session.commit()

    related_count = 0
    contradictions: list[ContradictionOut] = []
    seen_pairs: set[frozenset[int]] = set()
    principles_by_id = {p.id: p for p in principles}
    for p in principles:
        origin_audit = sessions_by_id.get(p.source_session_id)
        origin_skill_id = origin_audit.skill_id if origin_audit is not None else None
        link_principle(session, provider, p, exclude_skill_id=origin_skill_id)

    for link in session.exec(select(PrincipleLink)).all():
        if link.kind == LinkKind.related:
            related_count += 1
        elif link.kind == LinkKind.contradicts and link.target_kind.value == "principle":
            other = principles_by_id.get(link.target_id)
            source = principles_by_id.get(link.principle_id)
            if other is None or source is None or other.id is None or source.id is None:
                continue
            # The Librarian runs once per principle against the whole pool,
            # so a mutual contradiction between A and B can surface twice
            # (once from each side) — collapse to a single reported pair.
            pair = frozenset({source.id, other.id})
            if pair in seen_pairs:
                continue
            seen_pairs.add(pair)
            contradictions.append(
                ContradictionOut(
                    principle_a_id=source.id,
                    principle_a_title=source.title,
                    principle_b_id=other.id,
                    principle_b_title=other.title,
                    reason=link.reason,
                )
            )

    return RelinkResponse(
        principles_processed=len(principles),
        related_links_created=related_count,
        contradictions=contradictions,
    )
