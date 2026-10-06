"""Linker（agent 层）：判断新教训和候选之间的 related / contradicts（UT-19 ~ UT-21）。"""

import json

from app.agents.linker import LinkCandidate, Linker
from tests.helpers import ScriptedProvider

CANDIDATES = [
    LinkCandidate("principle", 11, "Check the log argument first", "When I solve a log equation, I first check that the argument is positive."),
    LinkCandidate("skill", 10, "Quadratic Functions", "Graphs, x-intercepts, maximum and minimum of quadratic functions."),
    LinkCandidate("skill", 12, "Trigonometric Functions", "Definitions and graphs of trigonometric functions."),
    LinkCandidate("principle", 13, "Negative discriminant means no solution", "When the discriminant is negative, I write 'no solution'."),
]


def judge(related=(), contradicts=(), candidates=CANDIDATES):
    raw = json.dumps(
        {
            "related": [{"ref": r, "reason": why} for r, why in related],
            "contradicts": [{"ref": r, "reason": why} for r, why in contradicts],
        },
        ensure_ascii=False,
    )
    provider = ScriptedProvider(linker=raw)
    result = Linker(provider).link("State the domain first", "State the domain before solving", "No real roots means no solutions", list(candidates))
    return result, provider


def test_ut19_valid_output_gives_the_links_with_their_candidates():
    result, _ = judge(related=[(0, "Check the domain before answering"), (1, "x-intercepts mean real roots")], contradicts=[(3, "Opposite actions on negative D")])

    assert [(c.kind, c.id, why) for c, why in result.related] == [
        ("principle", 11, "Check the domain before answering"),
        ("skill", 10, "x-intercepts mean real roots"),
    ]
    assert [(c.kind, c.id, why) for c, why in result.contradicts] == [("principle", 13, "Opposite actions on negative D")]


def test_ut20_an_unknown_ref_is_ignored():
    result, _ = judge(related=[(0, "ok"), (7, "No such candidate"), (-1, "negative")], contradicts=[(99, "No such candidate")])

    assert [c.id for c, _ in result.related] == [11]
    assert result.contradicts == []


def test_ut21_a_contradiction_pointing_at_a_skill_is_ignored():
    result, _ = judge(contradicts=[(1, "A node cannot contradict"), (3, "Lessons can")])

    assert [c.id for c, _ in result.contradicts] == [13]


def test_at_most_four_related_links_are_kept():
    many = [LinkCandidate("skill", i, f"Node {i}", "Description") for i in range(8)]

    result, _ = judge(related=[(i, "r") for i in range(8)], candidates=many)

    assert [c.id for c, _ in result.related] == [0, 1, 2, 3]


def test_reasons_are_cut_to_forty_characters():
    result, _ = judge(related=[(0, "x" * 80)])

    assert result.related[0][1] == "x" * 40


def test_the_same_ref_twice_links_once():
    result, _ = judge(related=[(0, "a"), (0, "b")])

    assert len(result.related) == 1


def test_non_json_output_means_no_links():
    provider = ScriptedProvider(linker="Nothing to link")

    result = Linker(provider).link("t", "b", None, CANDIDATES)

    assert result.related == [] and result.contradicts == []


def test_no_candidates_means_no_llm_call():
    provider = ScriptedProvider(linker="{}")

    result = Linker(provider).link("t", "b", None, [])

    assert (result.related, result.contradicts) == ([], [])
    assert provider.calls == []


def test_candidates_are_numbered_and_tagged_in_the_prompt():
    _, provider = judge(related=[(0, "r")])

    (prompt,) = provider.system_prompts("linker")
    assert "[0] P  Check the log argument first — When I solve a log equation" in prompt
    assert "[1] S  Quadratic Functions — Graphs, x-intercepts" in prompt
    assert "State the domain first: State the domain before solving (misconception: No real roots means no solutions)" in prompt


def test_candidate_text_is_cut_to_120_characters():
    long = [LinkCandidate("skill", 1, "Long description", "x" * 500)]

    _, provider = judge(candidates=long)

    (prompt,) = provider.system_prompts("linker")
    assert "x" * 120 in prompt and "x" * 121 not in prompt
