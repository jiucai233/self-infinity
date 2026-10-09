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

from app.models import EdgeKind, NodePosition, SkillEdge, SkillNode, SkillStatus

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
    "course_order",
    "descendant_ids",
    "open_every_course",
    "open_next",
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

    顺序有意义：只有一个节点的课程，那个节点是根（先判父节点）。还没展开的类别（unexpanded）
    虽然暂时没有子节点，也是中间节点。
    """
    has_parent = session.exec(
        select(SkillEdge.id).where(SkillEdge.to_id == skill.id, SkillEdge.kind == EdgeKind.contains).limit(1)
    ).first()
    if has_parent is None:
        return NodePosition.root
    if skill.unexpanded:
        return NodePosition.branch
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


def descendant_ids(session: Session, skill_id: int) -> list[int]:
    """Every node under `skill_id` along contains edges (through any parent), nearest first."""
    edges = session.exec(select(SkillEdge.from_id, SkillEdge.to_id).where(SkillEdge.kind == EdgeKind.contains)).all()
    children: dict[int, list[int]] = {}
    for parent, child in edges:
        children.setdefault(parent, []).append(child)
    found: list[int] = []
    seen = {skill_id}
    queue = [skill_id]
    while queue:
        for child in sorted(children.get(queue.pop(0), [])):
            if child not in seen:
                seen.add(child)
                found.append(child)
                queue.append(child)
    return found


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


# ---------------------------------------------------------------- unlocking: in order within a chapter
#
# Every course carries a learning order, a list laid over its tree: what a node contains comes
# before it, so a chapter follows its sections and the root, the course itself, comes last; a
# requires edge puts its prerequisite first; otherwise the place in the tree decides: siblings
# in the planner's order (it follows the outline, and nodes keep it as their ids), and the parts
# of a node broken down later where that node stands, not after everything older.
#
# The root's children are the chapters, and the player picks which chapter to work on: each
# chapter has one open node, the first one of it in that order not yet mastered (a chapter not
# broken down yet is its own first node). The root opens once every chapter is done. Mastered
# nodes stay open for a retake.


def course_order(session: Session, course_id: int) -> list[SkillNode]:
    """The course's nodes in learning order (see above)."""
    nodes = {n.id: n for n in session.exec(select(SkillNode).where(SkillNode.course_id == course_id)).all()}
    before: dict[int, set[int]] = {i: set() for i in nodes}
    for edge in session.exec(
        select(SkillEdge).where(col(SkillEdge.from_id).in_(nodes), col(SkillEdge.to_id).in_(nodes))
    ).all():
        if edge.kind == EdgeKind.contains:
            before[edge.from_id].add(edge.to_id)  # the parts before what contains them
        else:
            before[edge.to_id].add(edge.from_id)  # the prerequisite first
    place = _tree_places(session, nodes)
    order: list[SkillNode] = []
    left = set(nodes)
    while left:
        ready = [i for i in left if not before[i] & left]
        # A requires edge running against the tree can close a loop; the earliest node breaks it.
        pick = min(ready or left, key=lambda i: (place.get(i, len(place)), i))
        order.append(nodes[pick])
        left.remove(pick)
    return order


def _tree_places(session: Session, nodes: dict[int, SkillNode]) -> dict[int, int]:
    """node id -> its place in a pre-order walk of the main-parent tree, siblings by id."""
    main = {c: p for c, p in _main_parents(session).items() if c in nodes and p in nodes}
    children: dict[int, list[int]] = {}
    for child, parent in main.items():
        children.setdefault(parent, []).append(child)
    place: dict[int, int] = {}
    stack = sorted((i for i in nodes if i not in main), reverse=True)
    while stack:
        current = stack.pop()
        if current in place:
            continue
        place[current] = len(place)
        stack.extend(sorted(children.get(current, []), reverse=True))
    return place


def open_next(session: Session, course_id: int) -> list[int]:
    """Opens the first node of the course's order that is not mastered and locks the others that
    are not mastered. Returns the ids this call opened. Does not commit."""
    return [n.id for n in _line_up(session, course_id) if n.status == SkillStatus.available]


def open_every_course(session: Session) -> int:
    """[open_next] for every course: moves courses built under an older rule (they opened at the
    root) over to the order; on courses already in line it changes nothing. Returns how many
    nodes changed. Does not commit."""
    return sum(len(_line_up(session, c)) for c in session.exec(select(SkillNode.course_id).distinct()).all())


def _line_up(session: Session, course_id: int) -> list[SkillNode]:
    """Sets the statuses [open_next] describes; returns the nodes it changed."""
    order = course_order(session, course_id)
    chapter = _chapters(session, order)
    changed = []
    opened: set[int | None] = set()  # chapters (None: the root) whose open node is found
    for node in order:
        if node.status == SkillStatus.mastered:
            continue
        key = chapter.get(node.id)
        # The root waits for every chapter: it is last in the order, so any chapter still open
        # was met before it.
        want = SkillStatus.locked if key in opened or (key is None and opened) else SkillStatus.available
        opened.add(key)
        if node.status != want:
            node.status = want
            session.add(node)
            changed.append(node)
    return changed


def _chapters(session: Session, nodes: list[SkillNode]) -> dict[int, int]:
    """node id -> the root's child it sits under, along main parents; the root has none."""
    main = _main_parents(session)
    ids = {n.id for n in nodes}
    found: dict[int, int] = {}
    for node in nodes:
        current, seen = node.id, {node.id}
        while current in main and main[current] in ids and main[current] not in seen:
            parent = main[current]
            if parent not in main or main[parent] not in ids:  # parent is the root
                found[node.id] = current
                break
            seen.add(parent)
            current = parent
    return found
