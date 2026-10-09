"""Editing a course by hand (contract #41-#44), and courses inside courses.

- **Rename** a node, **add a part** under one, **delete** one with what is only under it (a part
  that also belongs elsewhere stays, under its other parent). The root is the course itself: it
  is renamed here but deleted with the course (#33).
- **A course inside a course**: a node can *be* another of the player's courses ("Computer
  Vision" in a CS course is the Computer Vision course). Its parts are that course's tree, so it
  has no children of its own and is not broken down or audited itself; the two are mastered
  together: passing that course's root masters the node, and a challenge that masters the node
  (from above) masters that course. Links are set by hand (#44) or found when a course is built
  (`auto_link`: a childless node titled like another course's root).

Every change runs unlocking again for the courses it touched.
"""

import re

from sqlmodel import Session, col, select

from app.models import Course, EdgeKind, SkillEdge, SkillNode, SkillStatus
from app.services.courses import purge_nodes
from app.services.tree import contains_children, contains_parents, descendant_ids, open_next
from app.utils import slugify


class EditRefused(Exception):
    """The edit does not fit the course; the router answers 400 with the message."""


# ---------------------------------------------------------------- editing nodes


def course_root(session: Session, course_id: int) -> SkillNode | None:
    """The course's node with no contains parent (the earliest, should there be more)."""
    nodes = session.exec(select(SkillNode).where(SkillNode.course_id == course_id).order_by(SkillNode.id)).all()
    ids = [n.id for n in nodes]
    children = set(
        session.exec(
            select(SkillEdge.to_id).where(SkillEdge.kind == EdgeKind.contains, col(SkillEdge.to_id).in_(ids))
        ).all()
    )
    return next((n for n in nodes if n.id not in children), None)


def rename(session: Session, node: SkillNode, title: str | None, description: str | None) -> SkillNode:
    if title is not None:
        node.title = title
    if description is not None:
        node.description = description
    session.add(node)
    session.commit()
    session.refresh(node)
    return node


def free_slug(session: Session, course_id: int, title: str) -> str:
    taken = set(session.exec(select(SkillNode.slug).where(SkillNode.course_id == course_id)).all())
    base = slugify(title) or "node"
    slug, n = base, 2
    while slug in taken:
        slug, n = f"{base}-{n}", n + 1
    return slug


def add_child(session: Session, parent: SkillNode, title: str, description: str | None) -> SkillNode:
    """A new leaf under `parent`. A node waiting to be broken down stays `unexpanded`: it has a
    part now, not all of them, and breaking it down (#38) adds the rest."""
    if parent.linked_course_id is not None:
        raise EditRefused("This node is another course: add parts in that course.")
    child = SkillNode(
        course_id=parent.course_id,
        slug=free_slug(session, parent.course_id, title),
        title=title,
        description=description or "",
        status=SkillStatus.locked,
    )
    session.add(child)
    session.flush()
    session.add(SkillEdge(from_id=parent.id, to_id=child.id, kind=EdgeKind.contains, is_primary=True))
    session.flush()
    open_next(session, parent.course_id)
    session.commit()
    session.refresh(child)
    return child


def doomed(session: Session, node: SkillNode) -> list[int]:
    """`node` and every node only under it: a part that also has a parent outside stays."""
    parents: dict[int, set[int]] = {}
    children: dict[int, set[int]] = {}
    for parent, child in session.exec(
        select(SkillEdge.from_id, SkillEdge.to_id).where(SkillEdge.kind == EdgeKind.contains)
    ).all():
        parents.setdefault(child, set()).add(parent)
        children.setdefault(parent, set()).add(child)
    gone = {node.id}
    pending = [node.id]
    while pending:
        for child in children.get(pending.pop(), ()):
            if child not in gone and parents[child] <= gone:
                gone.add(child)
                pending.append(child)
    return sorted(gone)


def delete_node(session: Session, node: SkillNode) -> list[int]:
    """Deletes `node` and what is only under it, with their history; returns the deleted ids."""
    if not contains_parents(session, node.id):
        raise EditRefused("This is the course itself: delete the course instead.")
    gone = doomed(session, node)
    # Parts that stay lose the edges from what goes; one that lost its main parent gets its next.
    for edge in session.exec(
        select(SkillEdge).where(
            col(SkillEdge.from_id).in_(gone), col(SkillEdge.to_id).not_in(gone), SkillEdge.kind == EdgeKind.contains
        )
    ).all():
        staying = edge.to_id
        session.delete(edge)
        session.flush()
        others = session.exec(
            select(SkillEdge)
            .where(SkillEdge.to_id == staying, SkillEdge.kind == EdgeKind.contains)
            .order_by(col(SkillEdge.is_primary).desc(), SkillEdge.id)
        ).all()
        if others and not any(e.is_primary for e in others):
            others[0].is_primary = True
            session.add(others[0])
    purge_nodes(session, gone)
    session.flush()
    open_next(session, node.course_id)
    session.commit()
    return gone


# ---------------------------------------------------------------- courses inside courses


def courses_inside(session: Session, course_id: int) -> set[int]:
    """Every course reachable from `course_id` through its nodes' links."""
    seen, pending = set(), [course_id]
    while pending:
        current = pending.pop()
        for linked in session.exec(
            select(SkillNode.linked_course_id).where(
                SkillNode.course_id == current, col(SkillNode.linked_course_id).is_not(None)
            )
        ).all():
            if linked not in seen:
                seen.add(linked)
                pending.append(linked)
    return seen


def can_link(session: Session, node: SkillNode, course_id: int) -> str | None:
    """Why `node` cannot be the course `course_id`, or None."""
    course = session.get(Course, course_id)
    if course is None or course.archived_at is not None:
        return "No such course."
    if course_id == node.course_id:
        return "A course cannot be inside itself."
    if not contains_parents(session, node.id):
        return "This is a course's root: link one of its parts."
    if contains_children(session, node.id):
        return "This node has parts of its own: delete them first, or link a node without parts."
    if node.course_id == course_id or node.course_id in courses_inside(session, course_id) | {course_id}:
        return "That course already holds this one: the two would contain each other."
    return None


def link(session: Session, node: SkillNode, course_id: int | None) -> SkillNode:
    if course_id is not None:
        problem = can_link(session, node, course_id)
        if problem:
            raise EditRefused(problem)
        node.unexpanded = False
    node.linked_course_id = course_id
    session.add(node)
    session.flush()
    sync_links(session)
    session.commit()
    session.refresh(node)
    return node


def sync_links(session: Session) -> set[int]:
    """Masters a linked node whose course's root is mastered, and the course (all of it, as
    tested out) of a linked node mastered from above; runs unlocking for the courses changed.
    Returns their ids. Does not commit."""
    touched: set[int] = set()
    changed = True
    while changed:
        changed = False
        for node in session.exec(select(SkillNode).where(col(SkillNode.linked_course_id).is_not(None))).all():
            course = session.get(Course, node.linked_course_id)
            root = course_root(session, node.linked_course_id) if course and course.archived_at is None else None
            if root is None:
                continue
            if root.status == SkillStatus.mastered and node.status != SkillStatus.mastered:
                node.status = SkillStatus.mastered
                node.mastery_score = root.mastery_score
                node.tested_out = root.tested_out
                session.add(node)
                touched.add(node.course_id)
                changed = True
            elif node.status == SkillStatus.mastered and root.status != SkillStatus.mastered:
                for part in [root.id, *descendant_ids(session, root.id)]:
                    other = session.get(SkillNode, part)
                    if other is not None and other.status != SkillStatus.mastered:
                        other.status = SkillStatus.mastered
                        other.tested_out = True
                        session.add(other)
                touched.add(root.course_id)
                changed = True
        session.flush()
    for course_id in touched:
        open_next(session, course_id)
    return touched


_BRACKETS = re.compile(r"[(（\[].*?[)）\]]")


def title_key(title: str) -> str:
    """A title for matching: no bracketed asides, case or punctuation."""
    return re.sub(r"[\W_]+", "", _BRACKETS.sub("", title).casefold())


def auto_link(session: Session, course_id: int) -> int:
    """Links found by title after `course_id` was built or grew: its childless nodes titled like
    another course's root become that course, and childless nodes of other courses titled like
    its root become it. Returns how many links were made. Does not commit."""
    roots = {}
    for course in session.exec(select(Course).where(col(Course.archived_at).is_(None))).all():
        root = course_root(session, course.id)
        if root is not None and title_key(root.title):
            roots[course.id] = title_key(root.title)
    made = 0
    own_key = roots.get(course_id)
    candidates = session.exec(select(SkillNode).where(col(SkillNode.linked_course_id).is_(None))).all()
    for node in candidates:
        if node.status == SkillStatus.mastered:
            continue
        key = title_key(node.title)
        if node.course_id == course_id:
            target = next((c for c, k in roots.items() if k == key and c != course_id), None)
        else:
            target = course_id if own_key and key == own_key else None
        if target is None or can_link(session, node, target):
            continue
        node.linked_course_id = target
        node.unexpanded = False
        session.add(node)
        session.flush()
        made += 1
    if made:
        sync_links(session)
    return made
