"""课程生成的编排（plan 6.5）：可选的课纲检索 → Planner → Structure Validator → 落库。

- 课纲检索是加分项，不是前置条件：搜索或 Syllabus Finder 出任何问题都只是降级成"没有
  参考"，Planner 照样凭自己的知识编排。
- Planner 的输出会先过 Structure Validator。唯一不能靠丢边修复的是规则 5（不是恰好一个
  根）：重试一次 Planner，再不行就失败。Planner 自己不可用（provider 出错、输出不是合法
  JSON 或形状不对）直接失败，不重试——JSON 层面的那一次重试已经在 provider 调用里做过了。
- 课程不限大小，分层生成：第一次写骨架，Planner 标了 `expand` 的类别存成 unexpanded，之后
  `expand_node` 单独展开（用户点开或学到那里时）。展开的结果过同一个 Structure Validator：
  被展开的节点充当这次输出的根。
- 每次回答只保留完整的层（whole_levels）：模型爱在部分类别下塞几个示例叶子，而有子节点的
  类别会被当成已拆完。
- 状态按学习顺序定（services/tree.py 的 open_next）：每章一个开放节点，根最后。
"""

import json
import logging
import re
from dataclasses import dataclass, replace

from sqlalchemy import update
from sqlmodel import Session, col, select

from app.agents.planner import PlannedCourse, PlannedNode, Planner, SyllabusText
from app.agents.syllabus import SyllabusFinder, SyllabusReference
from app.llm.base import LLMProvider
from app.models import Course, EdgeKind, SkillEdge, SkillNode, SkillStatus
from app.search.base import SearchProvider
from app.services.structure_validator import StructureError, ValidatedCourse, validate_structure
from app.services import course_match
from app.services.course_edit import auto_link
from app.services.tree import contains_children, contains_parents, course_graph, open_next

logger = logging.getLogger(__name__)

PLANNER_ATTEMPTS = 2  # the first try plus one retry (rule 5)
# Only recorded (rule 8): one answer's levels, the course has no depth limit.
LEVELS_PER_ANSWER = 6
# Not a size limit, a stop for a runaway model: no course grows past this.
MAX_COURSE_NODES = 500


class CourseGenerationError(Exception):
    """The course could not be produced; the router answers 502."""


class NotExpandable(Exception):
    """The node is already broken down (or being broken down); the router answers 400."""


class CourseFull(Exception):
    """The course reached MAX_COURSE_NODES; the router answers 409."""


@dataclass
class GeneratedCourse:
    course: Course
    nodes: list[SkillNode]
    edges: list[SkillEdge]
    # The topic asked for a course the player has: nothing new was built, and `added` nodes the
    # reference had and the course lacked were added to it.
    merged: bool = False
    added: int = 0


def find_syllabus(
    topic: str, provider: LLMProvider, search: SearchProvider
) -> SyllabusReference | None:
    try:
        return SyllabusFinder(provider, search).find(topic)
    except Exception:
        logger.warning("syllabus lookup failed, planning from the model's own knowledge", exc_info=True)
        return None


def plan_course(
    planner_provider: LLMProvider,
    topic: str,
    *,
    difficulty: str,
    syllabus: SyllabusReference | None,
    syllabus_text: SyllabusText | None = None,
) -> ValidatedCourse:
    planner = Planner(planner_provider)
    return _validated(
        lambda correction: planner.generate(
            topic, difficulty=difficulty, syllabus=syllabus, syllabus_text=syllabus_text, correction=correction
        ),
        check=(lambda validated: missing_items(validated, syllabus.outline)) if syllabus and not syllabus_text else None,
    )


_SKIPPABLE = re.compile(
    r"\b(intro(duction)?|overview|review|exam|midterm|final|project|presentation|summary|conclusion|wrap)", re.I
)
_WORD = re.compile(r"[^\W_]{3,}")
_STOP = {"and", "the", "for", "with", "its", "from", "into", "basics", "basic", "part", "parts"}


def _words(text: str) -> list[str]:
    return [w[:5] for w in _WORD.findall(text.casefold()) if w not in _STOP]


def missing_items(validated: ValidatedCourse, outline: list[str]) -> str | None:
    """The syllabus items the course's first level leaves out, as a correction for the Planner,
    or None. An item is there when a first-level title holds at least half of its words (by
    their first five letters, so "Deep RL: Value Methods" holds "Deep reinforcement learning:
    value methods"); an introduction, review or exam may be left out."""
    first = [set(_words(n.title)) for n in validated.nodes if validated.main_parent(n.slug) == validated.root_slug]
    missing = []
    for item in outline:
        words = set(_words(item))
        if not words or _SKIPPABLE.search(item):
            continue
        if not any(len(words & title) * 2 >= len(words) for title in first):
            missing.append(item)
    if not missing:
        return None
    return (
        "the first level leaves out these syllabus items: "
        + "; ".join(missing)
        + ". Each syllabus item is one node on the first level, titled as the item"
    )


def _validated(plan, root: PlannedNode | None = None, keep_levels: bool = True, check=None) -> ValidatedCourse:
    """Runs `plan(correction)` until the Structure Validator accepts it (one retry). With `root`
    (an expansion), the output hangs under that node: it is added as the root, and output nodes
    that name no parent get it as their parent."""
    correction: str | None = None
    for attempt in range(PLANNER_ATTEMPTS):
        try:
            planned: PlannedCourse = plan(correction)
        except Exception as exc:
            raise CourseGenerationError("the planner failed") from exc
        if root is not None:
            nodes = [n for n in planned.nodes if n.slug != root.slug]
            for node in nodes:
                if not node.parents:
                    node.parents = [root.slug]
            planned = PlannedCourse(nodes=[root, *nodes], requires=planned.requires)
        try:
            validated = validate_structure(planned, LEVELS_PER_ANSWER)
            validated = whole_levels(validated) if keep_levels else validated
        except StructureError as exc:
            logger.warning("planner output rejected on attempt %d: %s", attempt + 1, exc)
            correction = str(exc)
            continue
        # A softer problem (`check`) is retried once too, but the last answer is kept anyway.
        problem = check(validated) if check is not None and attempt + 1 < PLANNER_ATTEMPTS else None
        if problem is None:
            return validated
        logger.warning("planner output retried on attempt %d: %s", attempt + 1, problem)
        correction = problem
    raise CourseGenerationError(f"the planner output stayed unusable: {correction}")


def whole_levels(validated: ValidatedCourse) -> ValidatedCourse:
    """Keeps every level of the answer whole. Models fill their budget with a few sample leaves
    under some categories ("Operating Systems" → Paging, Banker's Algorithm) and leave the rest
    to expand, and a category with children counts as finished. So the first level holding a
    category left to expand is the last one kept: everything below it is dropped, and every
    category on it is left to expand, to be broken down whole in its own answer."""
    depth = {validated.root_slug: 0}
    pending = [validated.root_slug]
    children: dict[str, list[str]] = {}
    for node in validated.nodes:
        main = validated.main_parent(node.slug)
        if main is not None:
            children.setdefault(main, []).append(node.slug)
    while pending:
        slug = pending.pop()
        for child in children.get(slug, []):
            depth[child] = depth[slug] + 1
            pending.append(child)
    # A category with children is broken down, whatever its flag says.
    left = [n for n in validated.nodes if n.expand and n.slug in depth and not children.get(n.slug)]
    cut = min((depth[n.slug] for n in left), default=None)
    if cut is None:
        return validated
    kept = {slug for slug, d in depth.items() if d <= cut}
    dropped = len(validated.nodes) - len(kept)
    if dropped == 0:
        return validated
    logger.info("planner answer cut below level %d: %d nodes dropped", cut, dropped)
    nodes = []
    for node in validated.nodes:
        if node.slug not in kept:
            continue
        if depth[node.slug] == cut and children.get(node.slug):
            node.expand = True
        nodes.append(node)
    return replace(
        validated,
        nodes=nodes,
        parents={slug: [p for p in plist if p in kept] for slug, plist in validated.parents.items() if slug in kept},
        requires=[r for r in validated.requires if r.from_slug in kept and r.to_slug in kept],
        levels=cut + 1,
    )


def generate_course(
    session: Session,
    *,
    topic: str,
    difficulty: str,
    search_syllabus: bool,
    planner_provider: LLMProvider,
    syllabus_provider: LLMProvider,
    search_provider: SearchProvider,
    syllabus_text: SyllabusText | None = None,
) -> GeneratedCourse:
    """`syllabus_text`: syllabus text the caller already has (an uploaded file). It replaces the
    Syllabus Finder (no search, no finder call) and the course records its `source` with no URL."""
    syllabus = (
        find_syllabus(topic, syllabus_provider, search_provider)
        if search_syllabus and syllabus_text is None
        else None
    )
    existing = course_match.same_course(
        session, topic, embed=course_match.default_embed(), decide=course_match.default_decide()
    )
    if existing is not None:
        return merge_into(session, existing, planner_provider, syllabus=syllabus, syllabus_text=syllabus_text)
    validated = plan_course(
        planner_provider,
        topic,
        difficulty=difficulty,
        syllabus=syllabus,
        syllabus_text=syllabus_text,
    )
    return save_course(
        session,
        validated,
        topic=topic,
        settings={"difficulty": difficulty},
        syllabus=syllabus,
        source_name=syllabus_text.source if syllabus_text else None,
    )


def expand_node(session: Session, skill: SkillNode, planner_provider: LLMProvider) -> GeneratedCourse:
    """Breaks a node down into its parts and saves them under it: all of them for an unexpanded
    node, the missing ones for a node that has parts (filling it in).

    An unexpanded node is claimed first in one statement, so two requests cannot both expand
    it; if the Planner fails it is marked unexpanded again. A node that is another course is
    not broken down here. Raises NotExpandable, CourseFull or CourseGenerationError.
    """
    if skill.linked_course_id is not None:
        raise NotExpandable(skill.id)
    course = session.get(Course, skill.course_id)
    nodes = list(session.exec(select(SkillNode).where(SkillNode.course_id == skill.course_id)).all())
    if len(nodes) >= MAX_COURSE_NODES:
        raise CourseFull(skill.course_id)
    parts = [n.title for n in contains_children(session, skill.id)]
    claimed = bool(skill.unexpanded)
    if claimed:
        result = session.execute(
            update(SkillNode).where(col(SkillNode.id) == skill.id, col(SkillNode.unexpanded) == True).values(unexpanded=False)  # noqa: E712
        )
        session.commit()
        if result.rowcount != 1:
            raise NotExpandable(skill.id)
        session.refresh(skill)

    root = PlannedNode(slug=skill.slug, title=skill.title, description=skill.description, node_type=skill.node_type)
    settings = json.loads(course.settings_json or "{}") if course else {}
    planner = Planner(planner_provider)
    try:
        validated = _validated(
            lambda correction: planner.expand(
                course.topic if course else skill.title,
                skill.slug,
                skill.title,
                skill.description,
                _path(session, skill),
                [n.title for n in nodes if n.id != skill.id],
                difficulty=settings.get("difficulty", "standard"),
                correction=correction,
                parts=parts,
            ),
            root=root,
        )
    except CourseGenerationError:
        if claimed:
            skill.unexpanded = True
            session.add(skill)
            session.commit()
        raise

    _save_new(session, skill.course_id, validated, nodes, keep={skill.slug: skill})
    return _finish(session, course)


def merge_into(
    session: Session,
    course: Course,
    planner_provider: LLMProvider,
    *,
    syllabus: SyllabusReference | None,
    syllabus_text: SyllabusText | None,
) -> GeneratedCourse:
    """A course asked for again: what its reference adds goes into the course the player has;
    without a reference nothing changes."""
    before = len(session.exec(select(SkillNode.id).where(SkillNode.course_id == course.id)).all())
    if syllabus is None and syllabus_text is None:
        nodes, edges = course_graph(session, course.id)
        return GeneratedCourse(course=course, nodes=nodes, edges=edges, merged=True)
    revised = revise_course(session, course, planner_provider, syllabus=syllabus, syllabus_text=syllabus_text)
    revised.merged = True
    revised.added = max(0, len([n for n in revised.nodes if n.course_id == course.id]) - before)
    return revised


def revise_course(
    session: Session,
    course: Course,
    planner_provider: LLMProvider,
    *,
    syllabus: SyllabusReference | None = None,
    syllabus_text: SyllabusText | None = None,
) -> GeneratedCourse:
    """Adds what a reference (a syllabus found, or files uploaded) covers and the course lacks,
    each part under the node it belongs to; nothing is removed or renamed, progress stays. The
    course's source becomes the reference. Raises CourseFull or CourseGenerationError."""
    nodes = list(session.exec(select(SkillNode).where(SkillNode.course_id == course.id).order_by(SkillNode.id)).all())
    if len(nodes) >= MAX_COURSE_NODES:
        raise CourseFull(course.id)
    by_slug = {n.slug: n for n in nodes}
    parents = {n.slug: [p.slug for p in contains_parents(session, n.id)] for n in nodes}
    existing = [
        PlannedNode(slug=n.slug, title=n.title, description=n.description, parents=parents[n.slug], node_type=n.node_type)
        for n in nodes
    ]
    settings = json.loads(course.settings_json or "{}")
    planner = Planner(planner_provider)

    def plan(correction: str | None) -> PlannedCourse:
        planned = planner.revise(
            course.topic,
            _tree_lines(nodes, parents),
            syllabus=syllabus,
            syllabus_text=syllabus_text,
            difficulty=settings.get("difficulty", "standard"),
            correction=correction,
        )
        new = [n for n in planned.nodes if n.slug not in by_slug]
        return PlannedCourse(nodes=[*existing, *new], requires=planned.requires)

    validated = _validated(plan, keep_levels=False)
    keep = {slug: by_slug[slug] for slug in by_slug}
    _save_new(session, course.id, validated, nodes, keep=keep)
    if syllabus is not None:
        course.source_course, course.source_url = syllabus.course, syllabus.url
    elif syllabus_text is not None:
        course.source_course, course.source_url = syllabus_text.source, None
    session.add(course)
    return _finish(session, course)


def _match(session: Session, course_id: int) -> None:
    """After a course was built or grew: courses inside courses, by exact title, then judged
    (app/services/course_match.py). A failure only leaves them unmatched."""
    auto_link(session, course_id)
    try:
        course_match.place_around(
            session, course_id, embed=course_match.default_embed(), decide=course_match.default_decide()
        )
    except Exception:
        logger.warning("placing course %s among the others failed", course_id, exc_info=True)


def _tree_lines(nodes: list[SkillNode], parents: dict[str, list[str]]) -> str:
    """`slug: title` lines, indented under their main parent."""
    children: dict[str | None, list[SkillNode]] = {}
    for node in nodes:
        main = parents[node.slug][0] if parents[node.slug] else None
        children.setdefault(main, []).append(node)
    lines: list[str] = []
    pending = [(n, 0) for n in reversed(children.get(None, []))]
    seen: set[str] = set()
    while pending:
        node, depth = pending.pop()
        if node.slug in seen:
            continue
        seen.add(node.slug)
        lines.append(f"{'  ' * depth}{node.slug}: {node.title}")
        pending.extend((c, depth + 1) for c in reversed(children.get(node.slug, [])))
    return "\n".join(lines)


def _save_new(
    session: Session,
    course_id: int,
    validated: ValidatedCourse,
    nodes: list[SkillNode],
    keep: dict[str, SkillNode],
) -> None:
    """Saves the validated nodes not in `keep` (the course's own, by slug) and the edges among
    them and to the kept ones. A new node titled like one the course has, with no parts of its
    own, is left out."""
    existing = {n.slug: n for n in nodes}
    titles = {n.title.casefold() for n in nodes}
    # A plural, a hyphen or a casing away from a node the course has is that node.
    near = course_match.near_titles(
        [n.title for n in validated.nodes if n.slug not in keep], [n.title for n in nodes], course_match.default_embed()
    )
    rows: dict[str, SkillNode] = dict(keep)
    for node in validated.nodes:
        if node.slug in keep:
            continue
        has_children = any(node.slug in validated.parents.get(other.slug, []) for other in validated.nodes)
        if (node.title.casefold() in titles or node.title in near) and not has_children:
            continue  # already in the course
        rows[node.slug] = _add_node(session, course_id, _free_slug(node.slug, existing), node, has_children)
        existing[rows[node.slug].slug] = rows[node.slug]
        titles.add(node.title.casefold())
    _add_edges(session, validated, rows, skip_between=set(keep))


def _finish(session: Session, course: Course) -> GeneratedCourse:
    session.flush()
    open_next(session, course.id)
    _match(session, course.id)
    session.commit()
    session.refresh(course)
    graph_nodes, edges = course_graph(session, course.id)
    return GeneratedCourse(course=course, nodes=graph_nodes, edges=edges)


def _path(session: Session, skill: SkillNode) -> list[str]:
    """Titles from the root down to `skill`, along main parents."""
    path, current, seen = [skill.title], skill, {skill.id}
    while True:
        parents = contains_parents(session, current.id)
        if not parents or parents[0].id in seen:
            return path[::-1]
        current = parents[0]
        seen.add(current.id)
        path.append(current.title)


def _free_slug(slug: str, taken: dict[str, SkillNode]) -> str:
    if slug not in taken:
        return slug
    n = 2
    while f"{slug}-{n}" in taken:
        n += 1
    return f"{slug}-{n}"


def _add_node(session: Session, course_id: int, slug: str, node: PlannedNode, has_children: bool) -> SkillNode:
    row = SkillNode(
        course_id=course_id,
        slug=slug,
        title=node.title,
        description=node.description,
        status=SkillStatus.locked,
        node_type=node.node_type,
        # Only a node left without children can wait to be broken down.
        unexpanded=True if node.expand and not has_children else None,
    )
    session.add(row)
    session.flush()
    return row


def _add_edges(
    session: Session, validated: ValidatedCourse, rows: dict[str, SkillNode], skip_between: set[str] = frozenset()
) -> None:
    """The validated edges among `rows`; the ones between two `skip_between` nodes exist already."""
    for node in validated.nodes:
        if node.slug not in rows:
            continue
        for position, parent in enumerate(validated.parents[node.slug]):
            if parent not in rows or (parent in skip_between and node.slug in skip_between):
                continue
            session.add(
                SkillEdge(
                    from_id=rows[parent].id,
                    to_id=rows[node.slug].id,
                    kind=EdgeKind.contains,
                    is_primary=position == 0,
                )
            )
    for edge in validated.requires:
        if edge.from_slug in skip_between and edge.to_slug in skip_between:
            continue
        if edge.from_slug in rows and edge.to_slug in rows:
            session.add(
                SkillEdge(
                    from_id=rows[edge.from_slug].id,
                    to_id=rows[edge.to_slug].id,
                    kind=EdgeKind.requires,
                    reason=edge.reason,
                )
            )


def save_course(
    session: Session,
    validated: ValidatedCourse,
    *,
    topic: str,
    settings: dict,
    syllabus: SyllabusReference | None,
    source_name: str | None = None,
) -> GeneratedCourse:
    course = Course(
        topic=topic,
        settings_json=json.dumps(
            {
                **settings,
                # 每条规则处理了多少处，课程质量检查要看（plan 12.5）。
                "validation": {
                    "removals": {str(rule): count for rule, count in validated.removals.items()},
                    "levels": validated.levels,
                    "depth_exceeded": validated.depth_exceeded,
                },
            },
            ensure_ascii=False,
        ),
        source_course=syllabus.course if syllabus else source_name,
        source_url=syllabus.url if syllabus else None,
    )
    session.add(course)
    session.flush()

    rows: dict[str, SkillNode] = {}
    for node in validated.nodes:
        has_children = any(node.slug in plist for plist in validated.parents.values())
        rows[node.slug] = _add_node(session, course.id, node.slug, node, has_children)
    _add_edges(session, validated, rows)
    # Ids follow the planner's order, which the learning order breaks ties by.
    session.flush()
    open_next(session, course.id)
    _match(session, course.id)
    session.commit()
    session.refresh(course)

    nodes, edges = course_graph(session, course.id)
    return GeneratedCourse(course=course, nodes=nodes, edges=edges)
