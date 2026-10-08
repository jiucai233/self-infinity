"""Planner：解析 parents / requires、课纲进 prompt、坏输出报错（UT-01 ~ UT-03）。"""

import json

import pytest

from app.agents.planner import Planner, PlannerError, short_title
from app.agents.syllabus import SyllabusReference
from app.models import NodeType
from app.services.structure_validator import validate_structure
from tests.helpers import ScriptedProvider, planner_json

OUTPUT = planner_json(
    [
        ("math", [], "Math"),
        ("algebra", ["math"], "Algebra"),
        ("functions", ["math"], "Functions"),
        ("quadratic-equation", ["algebra"], "Quadratic Equations"),
        ("quadratic-function", ["functions", "algebra"], "Quadratic Functions"),
    ],
    [("quadratic-equation", "quadratic-function")],
)


def test_ut01_valid_output_gives_nodes_parents_and_requires_resolved_by_slug():
    planned = Planner(ScriptedProvider(planner=OUTPUT)).generate("Math")

    assert [n.slug for n in planned.nodes] == ["math", "algebra", "functions", "quadratic-equation", "quadratic-function"]
    assert planned.nodes[4].parents == ["functions", "algebra"]  # the first one is the main parent
    assert planned.nodes[0].parents == []
    assert [(r.from_slug, r.to_slug, r.reason) for r in planned.requires] == [
        ("quadratic-equation", "quadratic-function", "Reason")
    ]

    validated = validate_structure(planned, max_depth=4)
    assert validated.parents["quadratic-function"] == ["functions", "algebra"]
    assert validated.root_slug == "math"


def test_ut02_non_json_output_raises():
    provider = ScriptedProvider(planner="the course is: algebra, functions")

    with pytest.raises(PlannerError):
        Planner(provider).generate("Math")

    # JSON 层面的那一次重试已经用掉了：同一个提示词里的坏输出调用了两次。
    assert len(provider.calls_for("planner")) == 2


@pytest.mark.parametrize(
    "bad",
    [
        "[]",
        '"nodes"',
        '{"nodes": []}',
        '{"nodes": "algebra"}',
        '{"nodes": ["algebra"]}',
        '{"nodes": [{"slug": "a", "title": "  "}]}',
    ],
)
def test_ut02_wrong_shape_raises(bad):
    with pytest.raises(PlannerError):
        Planner(ScriptedProvider(planner=bad)).generate("Math")


def test_ut03_syllabus_section_is_in_the_prompt_when_provided():
    provider = ScriptedProvider(planner=OUTPUT)
    syllabus = SyllabusReference(
        course="State Univ. Linear Algebra (MATH101)", url="https://example.invalid/s", outline=["Vectors", "Matrices", "Determinants"]
    )

    Planner(provider).generate("Linear Algebra", syllabus=syllabus)

    (prompt,) = provider.system_prompts("planner")
    assert "Reference outline (State Univ. Linear Algebra (MATH101))" in prompt
    assert "1. Vectors" in prompt and "3. Determinants" in prompt


def test_ut03_no_syllabus_section_without_a_syllabus():
    provider = ScriptedProvider(planner=OUTPUT)

    Planner(provider).generate("Linear Algebra")

    (prompt,) = provider.system_prompts("planner")
    assert "Reference outline" not in prompt


def test_prompt_carries_the_course_settings_and_the_topic_goes_in_the_user_message():
    provider = ScriptedProvider(planner=OUTPUT)

    Planner(provider).generate("Statistics\n\nQ: Level?\nA: University", difficulty="deep")

    (messages,) = provider.calls_for("planner")
    system = messages[0]["content"]
    assert "Budget: at most 30 nodes" in system and "derivations" in system
    assert "Plan a new course" in system and "Soft Actor-Critic" in system
    assert messages[1] == {"role": "user", "content": "Statistics\n\nQ: Level?\nA: University"}


def test_a_correction_notice_is_appended_on_the_retry():
    provider = ScriptedProvider(planner=OUTPUT)

    Planner(provider).generate("Math", correction="expected exactly one node without parents, found 2")

    (messages,) = provider.calls_for("planner")
    assert "found 2" in messages[-1]["content"]


def test_over_long_titles_are_capped_at_forty_eight_characters():
    raw = json.dumps({"nodes": [{"slug": "root", "title": "x" * 60, "description": "d", "parents": []}]})

    planned = Planner(ScriptedProvider(planner=raw)).generate("Topic")

    assert planned.nodes[0].title == "x" * 48


def test_blank_parent_entries_are_not_parents():
    # 模型常把根节点写成 "parents": [""]。
    raw = json.dumps({"nodes": [{"slug": "root", "title": "Root", "description": "d", "parents": [""]}]})

    assert Planner(ScriptedProvider(planner=raw)).generate("Topic").nodes[0].parents == []


def test_unknown_node_type_defaults_to_concept_and_task_is_kept():
    raw = json.dumps(
        {
            "nodes": [
                {"slug": "root", "title": "Root", "description": "d", "parents": [], "node_type": "lesson"},
                {"slug": "t", "title": "To do", "description": "d", "parents": ["root"], "node_type": "task"},
            ]
        }
    )

    nodes = Planner(ScriptedProvider(planner=raw)).generate("Topic").nodes

    assert [n.node_type for n in nodes] == [NodeType.concept, NodeType.task]


def test_missing_slug_falls_back_to_one_derived_from_the_title():
    raw = json.dumps({"nodes": [{"title": "Quadratic Equation", "description": "d", "parents": []}]})

    assert Planner(ScriptedProvider(planner=raw)).generate("Topic").nodes[0].slug == "quadratic-equation"


def test_requires_without_endpoints_are_kept_for_the_validator_to_count():
    raw = json.dumps(
        {
            "nodes": [{"slug": "root", "title": "Root", "description": "d", "parents": []}],
            "requires": [{"from": "root"}, "junk", {"to": "root", "reason": "r"}],
        }
    )

    planned = Planner(ScriptedProvider(planner=raw)).generate("Topic")

    assert [(r.from_slug, r.to_slug) for r in planned.requires] == [("root", ""), ("", "root")]
    assert validate_structure(planned, max_depth=4).requires == []


@pytest.mark.parametrize(
    ("title", "short"),
    [
        ("Quadratic Equations", "Quadratic Equations"),
        # Over the 24 the prompt asks for, but under the cap: kept whole, not "Introduction to Differen".
        ("Introduction to Differential Equations", "Introduction to Differential Equations"),
        ("Limits and Continuity of Real Functions and Their Many Applications", "Limits and Continuity of Real Functions"),
        ("Vectors, Matrices, Determinants and Eigenvalues, Explained Slowly", "Vectors, Matrices, Determinants and Eigenvalues"),
        ("x" * 60, "x" * 48),
    ],
)
def test_a_long_title_is_cut_at_a_word_boundary_never_mid_word(title, short):
    assert short_title(title) == short
