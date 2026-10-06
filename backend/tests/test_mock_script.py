"""Mock LLM 和 Mock 搜索必须严格遵循 docs/api-contract.md 第 4 节的演示脚本。

Flutter 的 FakeApiClient 遵循同一份脚本，所以这里逐条核对，包括各个边界值。
都是通过真实的 agent 去调 Mock，这样 agent 的提示词和 Mock 的解析是否对得上也一并测到了。
"""

from types import SimpleNamespace

import pytest

from app.agents.auditor import Auditor
from app.agents.challenger import Challenger
from app.agents.clarifier import Clarifier
from app.agents.linker import LinkCandidate, Linker
from app.agents.planner import Planner
from app.agents.recorder import Recorder
from app.agents.syllabus import SyllabusFinder
from app.llm.mock import MockProvider
from app.models import NodePosition
from app.search.mock import MockSearchProvider
from app.services.structure_validator import validate_structure
from tests.helpers import text

MOCK = MockProvider()


# ---------------------------------------------------------------- 4.1 Clarifier


def test_41_statistics_gets_exactly_one_question():
    result = Clarifier(MOCK).clarify("Statistics")

    assert result.needs_clarification is True
    assert result.questions == ["Do you mean high-school probability and statistics, or university-level statistics?"]


def test_41_the_topic_only_has_to_contain_the_word_in_any_case():
    assert Clarifier(MOCK).clarify("Intro to Bayesian STATISTICS").needs_clarification is True


def test_41_the_korean_word_is_still_accepted_as_a_fallback():
    assert Clarifier(MOCK).clarify("통계").needs_clarification is True


@pytest.mark.parametrize("topic", ["Math", "High school math", "B-trees", "Python"])
def test_41_any_other_topic_needs_no_clarification(topic):
    result = Clarifier(MOCK).clarify(topic)

    assert (result.needs_clarification, result.questions) == (False, [])


# ---------------------------------------------------------------- 4.2 math course

# slug, title, contains parents (first = main), type
MATH_TABLE = [
    ("high-school-math", "High School Math", [], "concept"),
    ("algebra", "Algebra", ["high-school-math"], "concept"),
    ("functions", "Functions", ["high-school-math"], "concept"),
    ("calculus", "Calculus", ["high-school-math"], "concept"),
    ("quadratic-equation", "Quadratic Equations", ["algebra"], "concept"),
    ("discriminant", "Discriminant", ["quadratic-equation"], "concept"),
    ("root-coefficient", "Roots and Coefficients", ["quadratic-equation"], "concept"),
    ("sequences", "Sequences", ["algebra"], "concept"),
    ("linear-function", "Linear Functions", ["functions"], "concept"),
    ("quadratic-function", "Quadratic Functions", ["functions"], "concept"),
    ("sequence-limit", "Limits of Sequences", ["calculus", "sequences"], "concept"),
    ("derivative", "Derivatives", ["calculus"], "concept"),
]


@pytest.mark.parametrize("topic", ["Math", "high school MATH", "math\n\nQ: level?\nA: high school", "수학"])
@pytest.mark.parametrize("settings", [{}, {"node_count": 4, "max_depth": 2, "difficulty": "deep"}])
def test_42_math_course_is_the_twelve_node_table_whatever_the_settings(topic, settings):
    planned = Planner(MOCK).generate(topic, **settings)

    assert [(n.slug, n.title, n.parents, n.node_type.value) for n in planned.nodes] == MATH_TABLE
    assert all(n.description for n in planned.nodes)
    assert [(r.from_slug, r.to_slug, r.reason) for r in planned.requires] == [
        (
            "quadratic-equation",
            "quadratic-function",
            "The x-intercepts of a quadratic function are the roots of a quadratic equation.",
        ),
        ("linear-function", "quadratic-function", "You need the graph of a linear function first."),
        ("sequence-limit", "derivative", "The derivative is defined as a limit."),
    ]


def test_42_the_math_course_survives_the_validator_untouched():
    validated = validate_structure(Planner(MOCK).generate("Math"), max_depth=4)

    assert sum(validated.removals.values()) == 0
    assert validated.levels == 4
    assert len(validated.requires) == 3
    assert validated.parents["sequence-limit"] == ["calculus", "sequences"]  # two parents, calculus is the main one


def test_42_positions_are_root_1_branches_2_3_4_5_8_leaves_the_rest():
    validated = validate_structure(Planner(MOCK).generate("Math"), max_depth=4)
    ids = {slug: i for i, (slug, *_rest) in enumerate(MATH_TABLE, start=1)}
    has_children = {p for parents in validated.parents.values() for p in parents}

    def position(slug: str) -> NodePosition:
        if not validated.parents[slug]:
            return NodePosition.root
        return NodePosition.branch if slug in has_children else NodePosition.leaf

    by_position = {pos: sorted(ids[s] for s in ids if position(s) == pos) for pos in NodePosition}
    assert by_position == {
        NodePosition.root: [1],
        NodePosition.branch: [2, 3, 4, 5, 8],
        NodePosition.leaf: [6, 7, 9, 10, 11, 12],
    }


def test_42_every_math_title_fits_the_planner_title_limit():
    planned = Planner(MOCK).generate("Math")

    assert [n.title for n in planned.nodes] == [title for _slug, title, *_rest in MATH_TABLE]


def test_42_any_other_topic_gets_the_generic_course():
    planned = Planner(MOCK).generate("History")

    assert [(n.title, n.parents) for n in planned.nodes] == [
        ("History", []),
        ("Core Concepts", ["root"]),
        ("Key Methods", ["root"]),
        ("Applications", ["root"]),
        ("Core Concepts 1", ["core-concepts"]),
        ("Core Concepts 2", ["core-concepts"]),
        ("Key Methods 1", ["main-methods"]),
        ("Key Methods 2", ["main-methods"]),
        ("Applications 1", ["applications"]),
        ("Applications 2", ["applications"]),
    ]
    by_slug = {n.slug: n.title for n in planned.nodes}
    assert [(by_slug[r.from_slug], by_slug[r.to_slug]) for r in planned.requires] == [
        ("Core Concepts 1", "Key Methods 1"),
        ("Key Methods 1", "Applications 1"),
    ]
    assert sum(validate_structure(planned, max_depth=3).removals.values()) == 0


def test_42_the_generic_root_is_the_first_line_of_the_topic_cut_to_twenty_four_characters():
    long_topic = Planner(MOCK).generate("The history of the Roman Republic and Empire\n\nQ: scope?\nA: all")
    short_topic = Planner(MOCK).generate("History\n\nQ: scope?\nA: all")

    assert long_topic.nodes[0].title == "The history of the Roman"
    assert len(long_topic.nodes[0].title) == 24
    assert short_topic.nodes[0].title == "History"


class FixedSearch:
    """Wraps the Mock search so a test can see what was searched."""

    name = "fixed"

    def __init__(self):
        self._inner = MockSearchProvider()
        self.queries = []

    def search(self, query, limit=5):
        self.queries.append(query)
        return self._inner.search(query, limit)


def test_42_math_syllabus_is_found_with_the_first_mock_search_result_url():
    first_url = MockSearchProvider().search("Math")[0].url

    ref = SyllabusFinder(MOCK, FixedSearch()).find("Math")

    assert ref is not None
    assert ref.course == "High School Mathematics Curriculum (Ministry of Education)"
    assert ref.url == first_url == "https://example.invalid/1"
    assert 3 <= len(ref.outline) <= 30


def test_42_other_topics_are_not_found_as_a_syllabus():
    assert SyllabusFinder(MOCK, FixedSearch()).find("History") is None


def test_mock_search_is_deterministic_and_has_at_least_three_results():
    first = MockSearchProvider().search("anything")
    again = MockSearchProvider().search("anything")

    assert first == again
    assert len(first) >= 3
    assert all(hit.url.startswith("https://") and hit.title and hit.snippet for hit in first)
    assert len({hit.url for hit in first}) == len(first)


def test_mock_search_titles_are_english():
    hits = MockSearchProvider().search("anything")

    assert [hit.title for hit in hits] == [f"“anything” — resource {i}" for i in (1, 2, 3)]


# ---------------------------------------------------------------- 4.3 Audit


def dialogue(*answers: str) -> list[dict]:
    messages = [{"role": "assistant", "content": "Explain it from scratch."}]
    for i, answer in enumerate(answers):
        messages.append({"role": "user", "content": answer})
        if i < len(answers) - 1:
            messages.append({"role": "assistant", "content": "Tell me more."})
    return messages


def audit(*answers: str, lessons=None):
    return Auditor(MOCK).next_turn("Quadratic Equations", "Description", dialogue(*answers), lessons=lessons)


def test_43_first_answer_gets_the_default_probe():
    result = audit(text(500))

    assert result.is_verdict is False
    assert result.question == "Pick the most important term in your explanation and tell me what it means and why it matters."


def test_43_first_answer_with_lessons_refers_to_the_most_recent_one():
    newest = SimpleNamespace(title="New lesson", body="Body", misconception="No real roots means no solutions")
    older = SimpleNamespace(title="Old lesson", body="Body", misconception="Another misconception")

    result = audit(text(30), lessons=[newest, older])

    assert result.is_verdict is False
    assert result.question == (
        "You once thought “No real roots means no solutions”. How is this explanation different?"
    )


def test_43_a_lesson_without_a_misconception_falls_back_to_the_default_probe():
    lesson = SimpleNamespace(title="Lesson", body="Body", misconception=None)

    assert audit(text(30), lessons=[lesson]).question.startswith("Pick the most important term")


def test_43_lessons_only_matter_for_the_first_turn():
    lesson = SimpleNamespace(title="Lesson", body="Body", misconception="Misconception")

    assert audit(text(30), text(100), lessons=[lesson]).is_verdict is True


@pytest.mark.parametrize(("second", "passes"), [(49, False), (50, True)])
def test_43_pass_needs_eighty_characters_in_total(second, passes):
    result = audit(text(30), text(second))  # 30 + 49 = 79, 30 + 50 = 80

    assert result.is_verdict is True
    assert result.passed is passes


@pytest.mark.parametrize("marker", ["I don't know", "I DON'T KNOW", "I don’t know", "I'm not sure", "모르겠어요"])
def test_43_a_latest_answer_containing_the_marker_fails_however_long(marker):
    assert audit(text(100), text(300) + " " + marker).passed is False
    # Only the latest answer counts.
    assert audit(marker + " " + text(100), text(100)).passed is True


def test_43_pass_details():
    result = audit(text(30), text(100))  # n = 130

    assert result.passed is True
    assert result.score == min(95, 70 + 130 // 10) == 83
    assert result.gaps == []
    assert result.comment == "You explained the core idea and why it holds."


def test_43_score_is_capped_at_ninety_five():
    assert audit(text(30), text(1000)).score == 95
    assert audit(text(30), text(250)).score == 95  # n = 280 -> 70 + 28 = 98 -> 95
    assert audit(text(30), text(50)).score == 78  # n = 80


def test_43_fail_details():
    result = audit(text(10), text(20))

    assert result.passed is False
    assert result.score == 45
    assert result.gaps == [
        "You stated the definition but not why it works.",
        "You didn't cover the exceptions.",
    ]
    assert result.comment == "The answer stops at the conclusion and lacks reasons."


def test_43_later_turns_keep_giving_verdicts():
    assert audit(text(10), text(10), text(10)).is_verdict is True
    assert audit(text(10), text(10), text(10), text(200)).passed is True


def challenge(*answers: str):
    return Challenger(MOCK).review("Quadratic Equations", "Description", dialogue(*answers), [])


@pytest.mark.parametrize(("second", "overturned"), [(129, True), (130, False)])
def test_43_challenger_overturns_below_one_hundred_sixty_characters(second, overturned):
    result = challenge(text(30), text(second))  # 30 + 129 = 159, 30 + 130 = 160

    assert result.overturned is overturned
    if overturned:
        assert result.question == "Before I pass this: give one case where this idea does not hold, and explain why."


def test_43_so_a_medium_answer_is_challenged_once_and_a_long_one_passes_at_once():
    medium = audit(text(10), text(100))  # n = 110
    long = audit(text(10), text(200))  # n = 210

    assert medium.passed and challenge(text(10), text(100)).overturned
    assert long.passed and not challenge(text(10), text(200)).overturned


# ---------------------------------------------------------------- 4.4 Recorder / Linker


def test_44_recorder_script():
    lesson = Recorder(MOCK).distill(
        "Quadratic Equations", ["gap"], "I thought no real roots meant no solutions."
    )

    assert lesson.title == "Revisit “Quadratic Equations”"
    assert lesson.body == "When I explain “Quadratic Equations”, I give the reason before the conclusion."
    assert lesson.misconception == "I thought no real roots meant no solutions."


def test_44_recorder_cuts_to_the_field_limits():
    lesson = Recorder(MOCK).distill("T" * 40, [], "r" * 100)

    assert lesson.title == ("Revisit “" + "T" * 40 + "”")[:40]
    assert len(lesson.title) == 40
    assert lesson.body == ("When I explain “" + "T" * 40 + "”, I give the reason before the conclusion.")[:120]
    assert lesson.misconception == "r" * 60


def candidates():
    return [
        LinkCandidate("principle", 31, "Most recent lesson", "Body"),
        LinkCandidate("skill", 5, "Quadratic Equations", "Description"),
        LinkCandidate("principle", 29, "Older lesson", "Body"),
    ]


def test_44_linker_links_the_most_recent_other_principle():
    result = Linker(MOCK).link("Title", "Body", "Misconception", candidates())

    assert [(c.id, why) for c, why in result.related] == [(31, "Same concept, similar misconception")]
    assert result.contradicts == []


def test_44_linker_has_nothing_to_link_without_another_principle():
    only_skills = [LinkCandidate("skill", 5, "Quadratic Equations", "Description")]

    result = Linker(MOCK).link("Title", "Body", "Misconception", only_skills)

    assert result.related == [] and result.contradicts == []


def test_the_mock_refuses_a_prompt_it_has_no_script_for():
    with pytest.raises(ValueError):
        MOCK.complete([{"role": "system", "content": "[agent: nobody]\nhello"}])
