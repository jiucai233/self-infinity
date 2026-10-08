"""课程生成的编排（plan 6.5）：可选的课纲检索 → Planner → Structure Validator → 落库。

- 课纲检索是加分项，不是前置条件：搜索或 Syllabus Finder 出任何问题都只是降级成"没有
  参考"，Planner 照样凭自己的知识编排。
- Planner 的输出会先过 Structure Validator。唯一不能靠丢边修复的是规则 5（不是恰好一个
  根）：重试一次 Planner，再不行就失败。Planner 自己不可用（provider 出错、输出不是合法
  JSON 或形状不对）直接失败，不重试——JSON 层面的那一次重试已经在 provider 调用里做过了。
- 只有根节点是 available，其余全部 locked。
"""

import json
import logging
from dataclasses import dataclass

from sqlmodel import Session

from app.agents.planner import Planner, SyllabusText
from app.agents.syllabus import SyllabusFinder, SyllabusReference
from app.llm.base import LLMProvider
from app.models import Course, EdgeKind, SkillEdge, SkillNode, SkillStatus
from app.search.base import SearchProvider
from app.services.structure_validator import StructureError, ValidatedCourse, validate_structure
from app.services.tree import course_graph, open_next

logger = logging.getLogger(__name__)

PLANNER_ATTEMPTS = 2  # the first try plus one retry (rule 5)


class CourseGenerationError(Exception):
    """The course could not be produced; the router answers 502."""


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
    node_count: int,
    max_depth: int,
    difficulty: str,
    syllabus: SyllabusReference | None,
    syllabus_text: SyllabusText | None = None,
) -> ValidatedCourse:
    planner = Planner(planner_provider)
    correction: str | None = None
    for attempt in range(PLANNER_ATTEMPTS):
        try:
            planned = planner.generate(
                topic,
                node_count=node_count,
                max_depth=max_depth,
                difficulty=difficulty,
                syllabus=syllabus,
                syllabus_text=syllabus_text,
                correction=correction,
            )
        except Exception as exc:
            raise CourseGenerationError("the planner failed") from exc
        try:
            return validate_structure(planned, max_depth)
        except StructureError as exc:
            logger.warning("planner output rejected on attempt %d: %s", attempt + 1, exc)
            correction = str(exc)
    raise CourseGenerationError(f"the planner output stayed unusable: {correction}")


def generate_course(
    session: Session,
    *,
    topic: str,
    node_count: int,
    max_depth: int,
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
        node_count=node_count,
        max_depth=max_depth,
        difficulty=difficulty,
        syllabus=syllabus,
        syllabus_text=syllabus_text,
    )
    return save_course(
        session,
        validated,
        topic=topic,
        settings={"node_count": node_count, "max_depth": max_depth, "difficulty": difficulty},
        syllabus=syllabus,
        source_name=syllabus_text.source if syllabus_text else None,
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
        row = SkillNode(
            course_id=course.id,
            slug=node.slug,
            title=node.title,
            description=node.description,
            status=SkillStatus.locked,
            node_type=node.node_type,
        )
        session.add(row)
        session.flush()
        rows[node.slug] = row

    for node in validated.nodes:
        for position, parent in enumerate(validated.parents[node.slug]):
            session.add(
                SkillEdge(
                    from_id=rows[parent].id,
                    to_id=rows[node.slug].id,
                    kind=EdgeKind.contains,
                    is_primary=position == 0,
                )
            )
    for edge in validated.requires:
        session.add(
            SkillEdge(
                from_id=rows[edge.from_slug].id,
                to_id=rows[edge.to_slug].id,
                kind=EdgeKind.requires,
                reason=edge.reason,
            )
        )
    # Ids follow the planner's order, which the learning order breaks ties by.
    session.flush()
    open_next(session, course.id)
    session.commit()
    session.refresh(course)

    nodes, edges = course_graph(session, course.id)
    return GeneratedCourse(course=course, nodes=nodes, edges=edges)
