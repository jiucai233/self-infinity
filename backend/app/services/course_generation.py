"""课程生成的编排（plan 6.5）：可选的课纲检索 → Planner → Structure Validator → 落库。

- 课纲检索是加分项，不是前置条件：搜索或 Syllabus Finder 出任何问题都只是降级成"没有
  参考"，Planner 照样凭自己的知识编排。
- Planner 的输出会先过 Structure Validator。唯一不能靠丢边修复的是规则 5（不是恰好一个
  根）：重试一次 Planner，再不行就失败。Planner 自己不可用（provider 出错、输出不是合法
  JSON 或形状不对）直接失败，不重试——JSON 层面的那一次重试已经在 provider 调用里做过了。
- 课程不限大小，分层生成：第一次写骨架，Planner 标了 `expand` 的类别存成 unexpanded，之后
  `expand_node` 单独展开（用户点开或学到那里时）。展开的结果过同一个 Structure Validator：
  被展开的节点充当这次输出的根。
- 状态按学习顺序定（services/tree.py 的 open_next）：每章一个开放节点，根最后。
"""

import json
import logging
from dataclasses import dataclass

from sqlalchemy import update
from sqlmodel import Session, col, select

from app.agents.planner import PlannedCourse, PlannedNode, Planner, SyllabusText
from app.agents.syllabus import SyllabusFinder, SyllabusReference
from app.llm.base import LLMProvider
from app.models import Course, EdgeKind, SkillEdge, SkillNode, SkillStatus
from app.search.base import SearchProvider
from app.services.structure_validator import StructureError, ValidatedCourse, validate_structure
from app.services.tree import contains_parents, course_graph, open_next

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
        )
    )


def _validated(plan, root: PlannedNode | None = None) -> ValidatedCourse:
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
            return validate_structure(planned, LEVELS_PER_ANSWER)
        except StructureError as exc:
            logger.warning("planner output rejected on attempt %d: %s", attempt + 1, exc)
            correction = str(exc)
    raise CourseGenerationError(f"the planner output stayed unusable: {correction}")


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
    """Breaks an unexpanded node down into its parts and saves them under it.

    The node is claimed first in one statement, so two requests cannot both expand it; if the
    Planner fails it is marked unexpanded again. Raises NotExpandable, CourseFull or
    CourseGenerationError.
    """
    course = session.get(Course, skill.course_id)
    nodes = list(session.exec(select(SkillNode).where(SkillNode.course_id == skill.course_id)).all())
    if len(nodes) >= MAX_COURSE_NODES:
        raise CourseFull(skill.course_id)
    claimed = session.execute(
        update(SkillNode).where(col(SkillNode.id) == skill.id, col(SkillNode.unexpanded) == True).values(unexpanded=False)  # noqa: E712
    )
    session.commit()
    if claimed.rowcount != 1:
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
            ),
            root=root,
        )
    except CourseGenerationError:
        skill.unexpanded = True
        session.add(skill)
        session.commit()
        raise

    existing = {n.slug: n for n in nodes}
    titles = {n.title.casefold() for n in nodes}
    rows: dict[str, SkillNode] = {skill.slug: skill}
    for node in validated.nodes:
        if node.slug == skill.slug:
            continue
        has_children = any(node.slug in validated.parents.get(other.slug, []) for other in validated.nodes)
        if node.title.casefold() in titles and not has_children:
            continue  # already in the course
        rows[node.slug] = _add_node(session, skill.course_id, _free_slug(node.slug, existing), node, has_children)
        existing[rows[node.slug].slug] = rows[node.slug]
        titles.add(node.title.casefold())
    _add_edges(session, validated, rows)
    session.flush()
    open_next(session, skill.course_id)
    session.commit()
    session.refresh(course)
    graph_nodes, edges = course_graph(session, skill.course_id)
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


def _add_edges(session: Session, validated: ValidatedCourse, rows: dict[str, SkillNode]) -> None:
    for node in validated.nodes:
        if node.slug not in rows:
            continue
        for position, parent in enumerate(validated.parents[node.slug]):
            if parent not in rows:
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
    session.commit()
    session.refresh(course)

    nodes, edges = course_graph(session, course.id)
    return GeneratedCourse(course=course, nodes=nodes, edges=edges)
