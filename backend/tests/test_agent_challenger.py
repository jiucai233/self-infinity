"""Challenger（agent 层）：只看 pass，宁可维持原判（UT-12 ~ UT-15）。

它的行为要点是*会收敛*——一个能无限追杀的复核官等于永不通过，见 app/agents/challenger.py。
"""

import json

from app.agents.challenger import Challenger
from tests.helpers import BrokenProvider, ScriptedProvider

DIALOGUE = [
    {"role": "assistant", "content": "Explain it from scratch."},
    {"role": "user", "content": "A positive discriminant gives two distinct real roots."},
]


def review(output: str, misconceptions=(), provider=None):
    provider = provider or ScriptedProvider(challenger=output)
    return Challenger(provider).review("Quadratic Equations", "Repeated and complex roots", DIALOGUE, list(misconceptions)), provider


def test_ut12_uphold_is_not_an_overturn():
    result, _ = review('{"action": "uphold", "reason": "Covered the whole range"}')

    assert result.overturned is False
    assert result.question is None
    assert result.reason == "Covered the whole range"


def test_ut13_overturn_with_a_question_is_returned():
    raw = json.dumps(
        {"action": "overturn", "question": "What happens to the roots when the discriminant is 0?", "reason": "Evidence 1: repeated root"},
        ensure_ascii=False,
    )

    result, _ = review(raw)

    assert result.overturned is True
    assert result.question == "What happens to the roots when the discriminant is 0?"
    assert result.reason == "Evidence 1: repeated root"


def test_ut14_overturn_with_an_empty_question_is_treated_as_uphold():
    for raw in (
        '{"action": "overturn", "question": "  ", "reason": "r"}',
        '{"action": "overturn", "reason": "r"}',
        '{"action": "overturn", "question": null}',
    ):
        result, _ = review(raw)
        assert result.overturned is False, raw


def test_ut15_non_json_output_is_treated_as_uphold():
    for raw in ("Hmm", "[]", '"overturn"'):
        result, _ = review(raw)
        assert result.overturned is False, raw


def test_an_unknown_action_is_an_uphold():
    result, _ = review('{"action": "fail-them", "question": "q"}')

    assert result.overturned is False


def test_the_prompt_carries_both_challenge_sources_and_the_dialogue_follows():
    _, provider = review('{"action": "uphold", "reason": "r"}', misconceptions=["Thought no real roots meant no solutions"])

    (messages,) = provider.calls_for("challenger")
    system = messages[0]["content"]
    assert "Covers: Repeated and complex roots" in system
    assert "<misconceptions>\n- Thought no real roots meant no solutions\n</misconceptions>" in system
    assert messages[1:] == DIALOGUE


def test_no_misconceptions_reads_none():
    _, provider = review('{"action": "uphold", "reason": "r"}')

    assert "<misconceptions>\nnone\n</misconceptions>" in provider.system_prompts("challenger")[0]


def test_provider_errors_are_left_for_the_caller_to_swallow():
    import pytest

    with pytest.raises(RuntimeError):
        Challenger(BrokenProvider()).review("t", "d", DIALOGUE, [])
