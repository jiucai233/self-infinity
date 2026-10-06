"""节点在课程结构里的位置，全部由 contains 边决定（plan 第 4 节）。

节点在结构里的位置决定该怎么审计它：

- **叶子**下面什么都没有，它就是最具体的那个单元，问实现细节。
- **中间节点**的全部价值在于它统摄了下面挂的东西，所以该问的是那些孩子**之间**的
  关系与取舍——问"这是什么"等于浪费了它的位置。
- **根节点**是容器，问它自己没有意义，该问的是这门课的适用边界。

刻意用"有没有 contains 父/子"而不是"绝对深度"来判位置。同一棵课程里不同分支的深度
含义并不一致：一条分支可能挖到五层，另一条两层就到底，那么后者的叶子和前者的中间
节点深度相同、抽象程度却完全不同。
"""

from sqlmodel import Session, col, select

from app.models import EdgeKind, NodePosition, SkillEdge, SkillNode

__all__ = [
    "NodePosition",
    "child_titles",
    "course_graph",
    "contains_children",
    "contains_parents",
    "depth_map",
    "neighbor_ids",
    "node_depth",
    "node_position",
]


def contains_parents(session: Session, skill_id: int) -> list[SkillNode]:
    """主父节点在前，其余按边的创建顺序。"""
    return list(
        session.exec(
            select(SkillNode)
            .join(SkillEdge, SkillEdge.from_id == SkillNode.id)
            .where(SkillEdge.to_id == skill_id, SkillEdge.kind == EdgeKind.contains)
            .order_by(col(SkillEdge.is_primary).desc(), SkillEdge.id)
        ).all()
    )


def contains_children(session: Session, skill_id: int) -> list[SkillNode]:
    return list(
        session.exec(
            select(SkillNode)
            .join(SkillEdge, SkillEdge.to_id == SkillNode.id)
            .where(SkillEdge.from_id == skill_id, SkillEdge.kind == EdgeKind.contains)
            .order_by(SkillNode.id)
        ).all()
    )


def node_position(session: Session, skill: SkillNode) -> NodePosition:
    """没有 contains 父节点是根；有父节点没有子节点是叶子；其余是中间节点。

    顺序有意义：只有一个节点的课程，那个节点是根（先判父节点）。
    """
    has_parent = session.exec(
        select(SkillEdge.id).where(SkillEdge.to_id == skill.id, SkillEdge.kind == EdgeKind.contains).limit(1)
    ).first()
    if has_parent is None:
        return NodePosition.root
    has_child = session.exec(
        select(SkillEdge.id).where(SkillEdge.from_id == skill.id, SkillEdge.kind == EdgeKind.contains).limit(1)
    ).first()
    return NodePosition.leaf if has_child is None else NodePosition.branch


def child_titles(session: Session, skill: SkillNode) -> list[str]:
    """子节点标题，用于开场问题和让审计官问出"这些东西之间"的问题。"""
    return [c.title for c in contains_children(session, skill.id)]


def _main_parents(session: Session) -> dict[int, int]:
    """child id -> main parent id. 没有标主父的（手工造的数据）退化为最早的那条边。"""
    edges = session.exec(
        select(SkillEdge)
        .where(SkillEdge.kind == EdgeKind.contains)
        .order_by(col(SkillEdge.is_primary).desc(), SkillEdge.id)
    ).all()
    main: dict[int, int] = {}
    for edge in edges:
        main.setdefault(edge.to_id, edge.from_id)
    return main


def _depth_from(main: dict[int, int], skill_id: int) -> int:
    depth, current, seen = 0, skill_id, {skill_id}
    while current in main and main[current] not in seen:
        current = main[current]
        seen.add(current)
        depth += 1
    return depth


def depth_map(session: Session) -> dict[int, int]:
    """Depth of every node that has a contains edge; the root (and unknown ids) is 0."""
    main = _main_parents(session)
    return {skill_id: _depth_from(main, skill_id) for skill_id in main}


def node_depth(session: Session, skill: SkillNode) -> int:
    """Number of contains hops up the main-parent chain to the root (root = 0).

    A node with several parents is laid out under its main parent, so that is the
    chain that defines how deep it sits.
    """
    return _depth_from(_main_parents(session), skill.id)


def neighbor_ids(session: Session, skill_id: int) -> set[int]:
    """Direct contains / requires neighbours in either direction."""
    edges = session.exec(
        select(SkillEdge).where((SkillEdge.from_id == skill_id) | (SkillEdge.to_id == skill_id))
    ).all()
    ids = {e.from_id for e in edges} | {e.to_id for e in edges}
    ids.discard(skill_id)
    return ids


def course_graph(session: Session, course_id: int) -> tuple[list[SkillNode], list[SkillEdge]]:
    """All nodes of a course ordered by id, and all their edges (both kinds) ordered by id."""
    nodes = list(session.exec(select(SkillNode).where(SkillNode.course_id == course_id).order_by(SkillNode.id)).all())
    ids = [n.id for n in nodes]
    if not ids:
        return nodes, []
    edges = list(
        session.exec(select(SkillEdge).where(col(SkillEdge.from_id).in_(ids)).order_by(SkillEdge.id)).all()
    )
    return nodes, edges
