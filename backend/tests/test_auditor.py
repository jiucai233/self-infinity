"""Auditor：追问 / 裁决的解析、位置块、pacing、轮数上限（UT-06 ~ UT-11）。"""

import json
from types import SimpleNamespace

import pytest

from app.agents.auditor import FINAL_TURN_LINE, GENERIC_PROBE, Auditor, AuditorOutputError, format_lessons
from app.config import settings
from app.models import NodePosition, NodeType
from tests.helpers import ScriptedProvider, probe_json, verdict_json


def history(user_turns: int) -> list[dict]:
    messages = [{"role": "assistant", "content": "Explain it from scratch."}]
    for i in range(user_turns):
        messages.append({"role": "user", "content": f"Answer {i + 1}"})
        if i < user_turns - 1:
            messages.append({"role": "assistant", "content": f"Question {i + 1}"})
    return messages


def next_turn(output: str, user_turns: int = 1, **kwargs):
    provider = ScriptedProvider(auditor=output)
    result = Auditor(provider).next_turn("Quadratic Equations", "Judge the roots with the discriminant", history(user_turns), **kwargs)
    return result, provider


def system_prompt(provider: ScriptedProvider) -> str:
    return provider.system_prompts("auditor")[-1]


def test_ut06_probe_output_is_parsed_as_a_probe():
    result, _ = next_turn(probe_json("What is the discriminant?"))

    assert result.is_verdict is False
    assert result.question == "What is the discriminant?"


def test_ut07_verdict_output_is_parsed_with_pass_score_gaps_and_comment():
    result, _ = next_turn(verdict_json(False, 45, ["Could not explain complex roots", "Left out the repeated root"], "Stopped at the conclusion"))

    assert result.is_verdict is True
    assert result.passed is False
    assert result.score == 45
    assert result.gaps == ["Could not explain complex roots", "Left out the repeated root"]
    assert result.comment == "Stopped at the conclusion"


def test_ut08_non_json_below_the_limit_gives_the_generic_probe():
    result, provider = next_turn("Hmm, I am not sure", user_turns=1)

    assert result.is_verdict is False
    assert result.question == GENERIC_PROBE == "Could you explain that part a bit more specifically?"
    assert len(provider.calls_for("auditor")) == 2  # the JSON retry ran first


def test_ut09_probe_at_the_limit_is_forced_into_a_failing_verdict():
    result, _ = next_turn(probe_json(), user_turns=8, max_turns=8)

    assert result.is_verdict is True
    assert result.passed is False
    assert result.score == 0
    assert result.gaps and result.comment


def test_non_json_at_the_limit_is_an_error_not_a_fail():
    # A broken output is the model's fault: the router answers 502 and the user retries.
    with pytest.raises(AuditorOutputError):
        next_turn("not json", user_turns=4, max_turns=4)


def test_only_a_final_turn_tells_the_model_to_give_the_verdict():
    _, early = next_turn(probe_json(), user_turns=3, max_turns=8)
    _, at_limit = next_turn(verdict_json(False, 40), user_turns=8, max_turns=8)
    _, challenged = next_turn(verdict_json(True, 80), user_turns=3, max_turns=8, after_challenge=True)

    assert FINAL_TURN_LINE not in system_prompt(early)
    assert FINAL_TURN_LINE in system_prompt(at_limit)
    assert FINAL_TURN_LINE in system_prompt(challenged)


def test_after_a_challenge_another_probe_fails_with_its_own_comment():
    result, _ = next_turn(probe_json(), user_turns=3, max_turns=8, after_challenge=True)

    assert (result.is_verdict, result.passed, result.score) == (True, False, 0)
    assert "maximum" not in result.comment
    assert "follow-up" in result.comment


def test_the_output_example_does_not_anchor_a_pass_at_score_zero():
    _, provider = next_turn(probe_json())

    prompt = system_prompt(provider)
    assert '"pass": true, "score": 0' not in prompt
    assert "score: 0 to 100" in prompt


def test_probe_just_below_the_limit_is_still_a_probe():
    result, _ = next_turn(probe_json(), user_turns=7, max_turns=8)

    assert result.is_verdict is False


def test_a_verdict_at_the_limit_is_kept_as_given():
    result, _ = next_turn(verdict_json(True, 90), user_turns=8, max_turns=8)

    assert (result.passed, result.score) == (True, 90)


def test_default_limits_come_from_the_settings_by_node_type():
    concept, _ = next_turn(probe_json(), user_turns=settings.audit_max_turns, node_type=NodeType.concept)
    task_early, _ = next_turn(probe_json(), user_turns=settings.task_max_turns - 1, node_type=NodeType.task)
    task_at_limit, _ = next_turn(probe_json(), user_turns=settings.task_max_turns, node_type=NodeType.task)

    assert concept.is_verdict is True
    assert task_early.is_verdict is False
    assert task_at_limit.is_verdict is True


@pytest.mark.parametrize(
    ("node_type", "position", "marker"),
    [
        (NodeType.concept, NodePosition.leaf, "This is a specific topic."),
        (NodeType.concept, NodePosition.branch, "This is a category."),
        (NodeType.concept, NodePosition.root, "This is the whole field."),
        (NodeType.task, NodePosition.leaf, "This is an executable step."),
        (NodeType.task, NodePosition.branch, "This is an executable step."),
        (NodeType.task, NodePosition.root, "This is an executable step."),
    ],
)
def test_ut10_the_prompt_carries_exactly_the_matching_position_block(node_type, position, marker):
    _, provider = next_turn(probe_json(), node_type=node_type, position=position, child_titles=["One", "Two"])

    prompt = system_prompt(provider)
    all_markers = {
        "This is a specific topic.",
        "This is a category.",
        "This is the whole field.",
        "This is an executable step.",
    }
    assert marker in prompt
    for other in all_markers - {marker}:
        assert other not in prompt
    assert f"Position: {position.value}" in prompt


def test_parts_are_listed_for_root_and_branch_only():
    _, branch = next_turn(probe_json(), position=NodePosition.branch, child_titles=["Discriminant", "Roots and Coefficients"])
    _, root = next_turn(probe_json(), position=NodePosition.root, child_titles=["Algebra", "Functions"])
    _, leaf = next_turn(probe_json(), position=NodePosition.leaf, child_titles=["Ignored"])

    assert "Parts: Discriminant, Roots and Coefficients\n" in system_prompt(branch)
    assert "Parts: Algebra, Functions\n" in system_prompt(root)
    assert "Parts:" not in system_prompt(leaf)


def test_ut11_light_pacing_puts_the_pacing_line_in_the_prompt_and_leaves_the_limit_alone():
    _, normal = next_turn(probe_json(), pacing="normal")
    _, light = next_turn(probe_json(), pacing="light")

    assert "Pacing: normal" in system_prompt(normal)
    assert "Pacing: light" in system_prompt(light)
    assert "keep each question to one short sentence" in system_prompt(light)
    assert "Pacing never changes this standard." in system_prompt(light)

    # 轮数上限照旧：light 下同样在上限处被强制裁决，没到上限时不会。
    at_limit, _ = next_turn(probe_json(), user_turns=8, max_turns=8, pacing="light")
    below, _ = next_turn(probe_json(), user_turns=7, max_turns=8, pacing="light")
    assert at_limit.is_verdict is True and below.is_verdict is False


def test_an_unknown_pacing_falls_back_to_normal():
    _, provider = next_turn(probe_json(), pacing="frantic")

    assert "Pacing: normal" in system_prompt(provider)


def test_the_turn_limit_is_never_told_to_the_model():
    _, eight = next_turn(probe_json(), user_turns=1, max_turns=8)
    _, four = next_turn(probe_json(), user_turns=1, max_turns=4)

    assert system_prompt(eight) == system_prompt(four)


def test_the_dialogue_follows_the_system_prompt_unchanged():
    result_history = history(2)
    provider = ScriptedProvider(auditor=probe_json())

    Auditor(provider).next_turn("Quadratic Equations", "Description", result_history)

    (messages,) = provider.calls_for("auditor")
    assert messages[0]["role"] == "system"
    assert messages[1:] == result_history


def test_score_is_clamped_to_zero_through_one_hundred():
    high, _ = next_turn(verdict_json(True, 250))
    low, _ = next_turn(verdict_json(False, -30))

    assert high.score == 100
    assert low.score == 0


def test_a_verdict_without_a_usable_pass_or_score_is_not_trusted():
    for raw in (
        '{"action": "verdict", "score": 80, "gaps": []}',
        '{"action": "verdict", "pass": "maybe", "score": 80, "gaps": []}',
        '{"action": "verdict", "pass": true, "gaps": []}',
        '{"action": "verdict", "pass": true, "score": "high", "gaps": []}',
    ):
        result, _ = next_turn(raw, user_turns=1)
        assert result.is_verdict is False and result.question == GENERIC_PROBE, raw


def test_gaps_are_normalised_to_a_list_of_strings():
    single, _ = next_turn('{"action": "verdict", "pass": false, "score": 10, "gaps": "One", "comment": "c"}')
    mixed, _ = next_turn('{"action": "verdict", "pass": false, "score": 10, "gaps": ["a", 2, "", null], "comment": "c"}')
    missing, _ = next_turn('{"action": "verdict", "pass": true, "score": 90, "comment": "c"}')

    assert single.gaps == ["One"]
    assert mixed.gaps == ["a", "2"]
    assert missing.gaps == []


def test_at_most_three_gaps_are_kept_the_first_ones():
    gaps = ["most important", "second", "third", "a nitpick"]
    result, _ = next_turn(json.dumps({"action": "verdict", "pass": False, "score": 40, "gaps": gaps, "comment": "c"}))

    assert result.gaps == gaps[:3]


def test_the_verdict_grades_the_node_against_covers_not_the_whole_field():
    _, provider = next_turn(probe_json())
    prompt = system_prompt(provider)

    assert "grade this node, not the field" in prompt
    assert "would an expert mentor" in prompt and "Not:\n  could a stranger follow their words" in prompt
    assert "Details one would look up\n  while doing it" in prompt
    assert "Brevity is not a gap." in prompt
    assert "At most three gaps" in prompt
    assert "on the final turn, give the benefit of the doubt" in prompt


def test_a_reported_working_result_counts_as_the_check():
    _, provider = next_turn(probe_json())

    assert "a working result they\n  report" in system_prompt(provider)


def test_the_auditor_only_judges_and_never_gives_the_answer():
    _, provider = next_turn(probe_json())
    prompt = system_prompt(provider)

    assert "You only judge; you never teach. Never give the answer anywhere" in prompt
    assert "never the right version of it" in prompt


def test_pass_may_arrive_as_a_string():
    result, _ = next_turn('{"action": "verdict", "pass": "true", "score": 90, "gaps": [], "comment": "c"}')

    assert result.passed is True


def test_an_empty_probe_question_is_not_a_probe():
    result, _ = next_turn('{"action": "probe", "question": "  "}')

    assert result.question == GENERIC_PROBE


# ---------------------------------------------------------------- 教训如何进入 prompt


def lesson(title="State the domain", body="When solving, I state the domain.", misconception="No real roots means no solutions") -> SimpleNamespace:
    return SimpleNamespace(title=title, body=body, misconception=misconception)


def test_no_lessons_reads_none():
    _, provider = next_turn(probe_json(), lessons=[])

    assert "<lessons>\nnone\n</lessons>" in system_prompt(provider)


def test_lessons_are_listed_most_recent_first_with_their_misconception():
    newest = lesson("New lesson", "New body", "New misconception")
    older = lesson("Old lesson", "Old body", None)
    _, provider = next_turn(probe_json(), lessons=[newest, older])

    assert (
        "<lessons>\n- New lesson: New body (misconception: New misconception)\n- Old lesson: Old body\n</lessons>"
        in system_prompt(provider)
    )


def test_lesson_text_is_flattened_to_single_lines():
    flat = format_lessons([lesson("Title\nsecond line", "Body\n\nbreak", "Misconception\nbreak")])

    assert flat == "- Title second line: Body break (misconception: Misconception break)"
