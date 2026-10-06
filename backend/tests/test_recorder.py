"""Recorder：把失败变成一条教训（UT-16 ~ UT-18）。"""

import json

import pytest

from app.agents.recorder import MAX_BODY, MAX_MISCONCEPTION, MAX_TITLE, Recorder, RecorderError
from tests.helpers import ScriptedProvider

LESSON = {
    "title": "State the number set first",
    "body": "When I state a solution to an equation, I first say which number set it is over.",
    "misconception": "Thought no real roots meant no solutions",
}


def distill(raw: str | list[str], gaps=("Could not explain complex roots",)):
    provider = ScriptedProvider(recorder=raw)
    lesson = Recorder(provider).distill("Quadratic Equations", list(gaps), "I thought no real roots meant no solutions.")
    return lesson, provider


def test_ut16_valid_output_gives_the_three_fields():
    lesson, _ = distill(json.dumps(LESSON, ensure_ascii=False))

    assert (lesson.title, lesson.body, lesson.misconception) == (
        LESSON["title"],
        LESSON["body"],
        LESSON["misconception"],
    )


def test_ut17_a_missing_field_raises():
    for missing in LESSON:
        broken = {k: v for k, v in LESSON.items() if k != missing}
        with pytest.raises(RecorderError):
            distill(json.dumps(broken, ensure_ascii=False))


def test_ut17_an_empty_field_raises_too():
    with pytest.raises(RecorderError):
        distill(json.dumps({**LESSON, "title": "   "}, ensure_ascii=False))


def test_non_json_output_raises():
    with pytest.raises(RecorderError):
        distill("Here is your lesson")


def test_ut18_a_field_still_too_long_after_the_retry_is_cut():
    too_long = json.dumps(
        {"title": "a" * 50, "body": "b" * 200, "misconception": "c" * 90}, ensure_ascii=False
    )

    lesson, provider = distill(too_long)

    assert len(provider.calls_for("recorder")) == 2  # the first try plus exactly one retry
    assert (len(lesson.title), len(lesson.body), len(lesson.misconception)) == (MAX_TITLE, MAX_BODY, MAX_MISCONCEPTION)
    assert lesson.title == "a" * MAX_TITLE


def test_an_over_long_field_triggers_one_retry_and_the_corrected_output_wins():
    too_long = json.dumps({**LESSON, "title": "a" * 50}, ensure_ascii=False)

    lesson, provider = distill([too_long, json.dumps(LESSON, ensure_ascii=False)])

    assert lesson.title == LESSON["title"]
    retry = provider.calls_for("recorder")[1]
    assert retry[-1]["role"] == "user" and "title" in retry[-1]["content"]
    assert retry[-2] == {"role": "assistant", "content": too_long}


def test_an_unusable_retry_falls_back_to_cutting_the_first_output():
    too_long = json.dumps({**LESSON, "body": "b" * 200}, ensure_ascii=False)

    lesson, _ = distill([too_long, "This is not JSON", "This is not JSON"])

    assert lesson.body == "b" * MAX_BODY
    assert lesson.title == LESSON["title"]


def test_a_lesson_within_the_limits_is_not_retried():
    _, provider = distill(json.dumps(LESSON, ensure_ascii=False))

    assert len(provider.calls_for("recorder")) == 1


def test_fields_are_flattened_to_single_lines():
    raw = json.dumps({**LESSON, "misconception": "First line\nsecond line"}, ensure_ascii=False)

    lesson, _ = distill(raw)

    assert lesson.misconception == "First line second line"


def test_the_prompt_names_the_node_and_the_gaps_and_the_reflection_is_the_user_message():
    _, provider = distill(json.dumps(LESSON, ensure_ascii=False), gaps=("Could not explain complex roots", "Left out the repeated root"))

    (messages,) = provider.calls_for("recorder")
    system = messages[0]["content"]
    assert "Node: Quadratic Equations\n" in system
    assert "Gaps found by the examiner: Could not explain complex roots; Left out the repeated root" in system
    assert messages[1] == {"role": "user", "content": "I thought no real roots meant no solutions."}


def test_no_gaps_are_spelled_out():
    _, provider = distill(json.dumps(LESSON, ensure_ascii=False), gaps=())

    assert "(none recorded)" in provider.system_prompts("recorder")[0]
