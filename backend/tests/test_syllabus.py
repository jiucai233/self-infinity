"""Syllabus Finder：找一份真实课纲当参考，URL 只来自搜索结果（UT-24、UT-25）。

最重要的性质是宁可判定没找到：编造一个来源比没有来源糟糕得多。
"""

import json

from app.agents.syllabus import SyllabusFinder
from app.search.base import SearchHit
from tests.helpers import BrokenProvider, ScriptedProvider


class FakeSearch:
    name = "fake"

    def __init__(self, hits: list[SearchHit] | None = None, fail: bool = False):
        self.hits = hits if hits is not None else HITS
        self.fail = fail
        self.queries: list[str] = []
        self.pages: list[bool] = []

    def search(self, query: str, limit: int = 5, *, pages: bool = False) -> list[SearchHit]:
        self.queries.append(query)
        self.pages.append(pages)
        if self.fail:
            raise RuntimeError("search down")
        return self.hits


HITS = [
    SearchHit(title="Linear algebra summary blog", url="https://blog.example/la", snippet="A short, easy write-up of linear algebra"),
    SearchHit(
        title="MATH 2210 Linear Algebra",
        url="https://math.example.edu/2210",
        snippet="Week 1 systems of equations. Week 2 matrices. Week 3 determinants.",
    ),
    SearchHit(title="Lecture playlist", url="https://video.example/list", snippet="A collection of videos"),
]


def found(index: int, course: str = "Example Univ. MATH 2210", outline=("Systems of equations", "Matrices", "Determinants")) -> str:
    return json.dumps({"found": True, "index": index, "course": course, "outline": list(outline)}, ensure_ascii=False)


def test_ut24_found_gives_course_outline_and_the_url_of_the_indexed_result():
    ref = SyllabusFinder(ScriptedProvider(syllabus_finder=found(1)), FakeSearch()).find("Linear Algebra")

    assert ref is not None
    assert ref.course == "Example Univ. MATH 2210"
    assert ref.outline == ["Systems of equations", "Matrices", "Determinants"]
    assert ref.url == "https://math.example.edu/2210"


def test_ut25_index_outside_the_result_list_is_treated_as_not_found():
    for index in (3, 99, -1):
        assert SyllabusFinder(ScriptedProvider(syllabus_finder=found(index)), FakeSearch()).find("Linear Algebra") is None


def test_url_never_comes_from_the_model():
    forged = json.dumps(
        {"found": True, "index": 1, "course": "X", "outline": ["a", "b", "c"], "url": "https://forged.invalid/evil"}
    )

    ref = SyllabusFinder(ScriptedProvider(syllabus_finder=forged), FakeSearch()).find("Linear Algebra")

    assert ref.url == "https://math.example.edu/2210"


def test_not_found_is_a_normal_answer():
    provider = ScriptedProvider(syllabus_finder='{"found": false}')

    assert SyllabusFinder(provider, FakeSearch()).find("Linear Algebra") is None


def test_outline_must_have_three_to_thirty_items():
    for outline in ([], ["a"], ["a", "b"], [f"t{i}" for i in range(31)]):
        provider = ScriptedProvider(syllabus_finder=found(1, outline=outline))
        assert SyllabusFinder(provider, FakeSearch()).find("Linear Algebra") is None, len(outline)

    for outline in (["a", "b", "c"], [f"t{i}" for i in range(30)]):
        provider = ScriptedProvider(syllabus_finder=found(1, outline=outline))
        assert SyllabusFinder(provider, FakeSearch()).find("Linear Algebra") is not None, len(outline)


def test_a_reference_without_a_course_name_is_useless():
    provider = ScriptedProvider(syllabus_finder=found(1, course="  "))

    assert SyllabusFinder(provider, FakeSearch()).find("Linear Algebra") is None


def test_unusable_model_output_means_not_found():
    for raw in ("not json", "[]", '{"found": true}', '{"found": true, "index": "x", "course": "c", "outline": []}'):
        assert SyllabusFinder(ScriptedProvider(syllabus_finder=raw), FakeSearch()).find("Linear Algebra") is None, raw


def test_no_search_results_means_no_llm_call():
    provider = ScriptedProvider(syllabus_finder=found(0))

    assert SyllabusFinder(provider, FakeSearch(hits=[])).find("Linear Algebra") is None
    assert provider.calls == []


def test_a_failed_search_degrades_to_not_found():
    assert SyllabusFinder(ScriptedProvider(syllabus_finder=found(0)), FakeSearch(fail=True)).find("Linear Algebra") is None


def test_searches_the_first_line_three_ways_and_numbers_the_results_with_their_domains():
    provider = ScriptedProvider(syllabus_finder=found(1))
    search = FakeSearch()

    SyllabusFinder(provider, search).find("Linear Algebra\n\nQ: Level?\nA: University")

    assert sorted(search.queries) == [  # the first line of the topic only
        "Linear Algebra course syllabus",
        "Linear Algebra official documentation tutorial",
        "Linear Algebra syllabus",
    ]
    assert search.pages == [True, True, True]  # page text, not just snippets
    (prompt,) = provider.system_prompts("syllabus_finder")
    assert "Topic: Linear Algebra\n\nQ: Level?\nA: University\nResults:" in prompt
    assert "[1] MATH 2210 Linear Algebra | math.example.edu | Week 1" in prompt


def test_results_from_all_queries_are_merged_without_duplicate_urls():
    provider = ScriptedProvider(syllabus_finder=found(0))
    search = FakeSearch()

    SyllabusFinder(provider, search).find("Linear Algebra")  # every query returns the same three hits

    (prompt,) = provider.system_prompts("syllabus_finder")
    assert prompt.count("\n[") == 3


def test_a_failing_provider_raises_for_the_caller_to_degrade():
    # find() itself lets provider errors out; app.services.course_generation.find_syllabus turns them into "not found".
    import pytest

    with pytest.raises(RuntimeError):
        SyllabusFinder(BrokenProvider(), FakeSearch()).find("Linear Algebra")


def test_the_judge_reads_the_start_of_each_page():
    page = "SO-101 guide. 1. Assemble the arms 2. Configure the motors 3. Calibrate 4. Teleoperate " + "x" * 5000
    hits = [
        SearchHit(title="SO-101 - LeRobot docs", url="https://huggingface.co/docs/lerobot/so101", snippet="Build the arm", content=page),
        SearchHit(title="A blog", url="https://blog.example/so101", snippet="My build"),
    ]
    provider = ScriptedProvider(syllabus_finder=found(0, course="LeRobot docs: SO-101", outline=("Assemble", "Configure", "Calibrate")))

    reference = SyllabusFinder(provider, FakeSearch(hits)).find("SO-ARM101 robot arm")

    (prompt,) = provider.system_prompts("syllabus_finder")
    assert "    Page: SO-101 guide. 1. Assemble the arms" in prompt
    assert "x" * 3100 not in prompt  # each page is cut
    assert "[1] A blog | blog.example | My build\n[" not in prompt  # no Page line without a page
    assert reference.course == "LeRobot docs: SO-101"
    assert reference.url == "https://huggingface.co/docs/lerobot/so101"


def test_at_most_eight_candidates_reach_the_judge():
    hits = [SearchHit(title=f"r{i}", url=f"https://e.example/{i}", snippet="s") for i in range(12)]
    provider = ScriptedProvider(syllabus_finder=json.dumps({"found": False}))

    SyllabusFinder(provider, FakeSearch(hits)).find("Linear Algebra")

    (prompt,) = provider.system_prompts("syllabus_finder")
    assert "[7] r7" in prompt and "[8]" not in prompt


def test_a_long_page_shows_its_start_and_its_most_list_like_stretch():
    from app.agents.syllabus import page_excerpt

    page = "MIT 18.06 Linear Algebra syllabus. " + "Prose about grading. " * 300 + " ".join(
        f"Lecture {i}: topic {i}." for i in range(1, 30)
    ) + " Footer text." * 200

    excerpt = page_excerpt(page)

    assert excerpt.startswith("MIT 18.06 Linear Algebra syllabus.")
    assert "Lecture 1: topic 1." in excerpt and "Lecture 20: topic 20." in excerpt
    assert len(excerpt) < 3100
