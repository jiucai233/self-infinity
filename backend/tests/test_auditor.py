"""Auditor：点评 + 追问 / 裁决的解析、知识点、位置块、pacing、轮数上限（UT-06 ~ UT-11）。"""

import json
from types import SimpleNamespace

import pytest

from app.agents.auditor import (
    FINAL_TURN_LINE,
    GENERIC_PROBE,
    Auditor,
    AuditorOutputError,
    began_with,
    format_lessons,
)
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
    assert "Light pacing: the question is a few words." in system_prompt(light)
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
    assert "would an expert mentor believe" in prompt and "Not: could a\n  stranger follow their words" in prompt
    assert "Details one would\n  look up while doing it" in prompt
    assert "Brevity is not a gap." in prompt
    assert "At most three\n  gaps" in prompt
    assert "on the final turn, give the benefit of the doubt" in prompt


def test_a_reported_working_result_counts_as_the_check():
    _, provider = next_turn(probe_json())

    assert "a working result they\n  report" in system_prompt(provider)


def test_the_auditor_is_a_student_and_the_user_does_the_teaching():
    _, provider = next_turn(probe_json())
    prompt = system_prompt(provider)

    assert "You are the student in a Feynman audit. The user is your teacher" in prompt
    assert "You are not setting an exam." in prompt
    assert "your reaction to what they just taught, then the one place\nthat lost you" in prompt
    assert "The\n  user does the teaching here, not you." in prompt


def test_she_speaks_as_a_student_and_judges_as_an_expert():
    _, provider = next_turn(probe_json())
    prompt = system_prompt(provider)

    assert "HOW YOU SPEAK: as a student to the person teaching you." in prompt
    assert "Never the words of a teacher or an examiner" in prompt
    # The verdict is not in the student's voice: it is the record.
    assert "Here you stop playing the\nstudent: you judge with everything you know." in prompt
    assert 'Only the verdict\'s "feedback" is still the student speaking.' in prompt


def test_a_wrong_claim_gets_a_second_try_before_the_auditor_explains_it():
    _, provider = next_turn(probe_json())
    prompt = system_prompt(provider)

    assert "A wrong claim: be puzzled, and let the puzzlement be your question." in prompt
    assert "Never say what is right instead" in prompt
    assert "say it as something you went and looked up" in prompt
    assert "Give the right version only when they have tried that part twice" in prompt
    assert "Never reveal or hint at the answer to what you are asking now" in prompt
    # What she explained is not the user's own understanding; a second try of their own is.
    assert "What you explained does not count for them." in prompt
    assert "the first time or on the\n  second try after you said what did not hold" in prompt


def test_questions_come_out_of_what_the_user_said_not_from_an_exam_paper():
    _, provider = next_turn(probe_json())
    prompt = system_prompt(provider)

    assert "QUESTIONING: one question per turn, and it comes out of what they said." in prompt
    assert "They used a term or a step without explaining it" in prompt
    assert "Two things they said do not connect" in prompt
    assert "Never the wording of an exam paper: no situation set up from nothing" in prompt
    assert "A question never states its own answer" in prompt
    assert "Never ask the same question twice in the same words" in prompt
    assert "never ask\n  for something they have already told you" in prompt
    assert "At most two questions on one point" in prompt


def test_a_recited_explanation_is_checked_once_and_a_what_if_is_kept_for_that():
    _, provider = next_turn(probe_json())
    prompt = system_prompt(provider)

    assert "in the words of a textbook, with no reason of\n   their own" in prompt
    assert "Once per point." in prompt
    assert 'A "what if" (something removed, swapped or pushed to an extreme) is\n  allowed only under 4' in prompt
    assert "no trick\n  questions" in prompt


def test_the_auditor_does_not_push_a_user_who_has_had_enough():
    _, provider = next_turn(probe_json())

    assert "do not\n  push. Explain it briefly, count it as missed and go on" in system_prompt(provider)


def test_she_is_shown_how_her_earlier_turns_began_and_told_to_begin_otherwise():
    history = [
        {"role": "assistant", "content": "I have never learned it. Teach it to me from the start."},
        {"role": "user", "content": "It is a sum."},
        {"role": "assistant", "content": "Oh, so it adds things up.\n\nWhat does it add?"},
        {"role": "user", "content": "The terms."},
        {"role": "assistant", "content": "我听懂了：它把各项加起来。\n\n各项是什么？"},
        {"role": "user", "content": "The numbers in the series."},
    ]

    # Her first clause each time, the opening template left out.
    assert began_with(history) == ["Oh", "我听懂了"]
    assert began_with(history[:2]) == []

    provider = ScriptedProvider(auditor=probe_json())
    Auditor(provider).next_turn("Series", "Sums of terms", history)
    prompt = system_prompt(provider)
    assert 'Your earlier turns began: "Oh", "我听懂了". Begin this one with none of those words' in prompt
    assert "No two turns sound alike" in prompt

    _, first = next_turn(probe_json())  # nothing of hers yet: no such line
    assert "Your earlier turns began" not in system_prompt(first)


def test_a_question_at_the_end_of_the_feedback_is_dropped_so_it_is_asked_once():
    doubled, _ = next_turn(
        json.dumps(
            {
                "action": "probe",
                "feedback": "You showed why order matters. If two position vectors are swapped, what happens?",
                "question": "If two position vectors are swapped, what happens?",
            }
        )
    )
    chinese, _ = next_turn(json.dumps({"action": "probe", "feedback": "这一步我跟上了。那后面呢？", "question": "后面呢？"}))
    only, _ = next_turn(json.dumps({"action": "probe", "feedback": "What then?", "question": "What then?"}))

    assert doubled.feedback == "You showed why order matters."
    assert chinese.feedback == "这一步我跟上了。"
    assert only.feedback is None and only.question == "What then?"


def test_feedback_comes_with_the_probe_and_with_the_verdict():
    probe, _ = next_turn(json.dumps({"action": "probe", "feedback": " Half right. ", "question": "Why?"}))
    verdict, _ = next_turn(
        json.dumps({"action": "verdict", "feedback": "Right.", "pass": True, "score": 90, "gaps": [], "comment": "c"})
    )
    bare, _ = next_turn(probe_json())

    assert (probe.feedback, probe.question) == ("Half right.", "Why?")
    assert verdict.feedback == "Right."
    assert bare.feedback is None  # optional: a model that leaves it out still asks


# ---------------------------------------------------------------- 知识点

POINTS = [{"title": "Discriminant", "note": None}, {"title": "Vieta's formulas", "note": "Mixed up the signs."}]


def test_without_points_the_prompt_has_no_points_block():
    _, provider = next_turn(probe_json())
    prompt = system_prompt(provider)

    assert "Points, the knowledge points" not in prompt and '"points" has one entry' not in prompt
    assert 'A part of "Covers" (or of Parts, when listed) they have not come to yet' in prompt


def test_the_points_to_examine_are_listed_with_the_note_of_the_last_miss():
    _, provider = next_turn(probe_json(), points=POINTS, settled=["Completing the square"])
    prompt = system_prompt(provider)

    assert "your own list of\nwhat the explanation has to reach, not an agenda to walk through" in prompt
    assert "- Discriminant\n- Vieta's formulas — Mixed up the signs.\n" in prompt
    # Last time's miss is listened for, not handed back as a leading question.
    assert "never bring it up yourself" in prompt
    assert "do not ask about them again: Completing the square\n" in prompt
    assert "A point of Points they have not come to yet: ask them to teach it" in prompt
    assert "Every point has to be taught or asked about before the\n   verdict." in prompt
    assert "pass is true only when every point is ok." in prompt


def test_a_probe_names_the_point_it_examines():
    named, _ = next_turn(json.dumps({"action": "probe", "point": "discriminant", "question": "Why?"}), points=POINTS)
    unknown, _ = next_turn(json.dumps({"action": "probe", "point": "Matrices", "question": "Why?"}), points=POINTS)

    assert named.point == "Discriminant"  # matched without case, given back as the audit has it
    assert unknown.point is None


def points_verdict(passed: bool, points) -> str:
    return json.dumps(
        {"action": "verdict", "pass": passed, "score": 70, "points": points, "gaps": [], "comment": "c"}
    )


def test_a_verdict_gives_each_point_its_result_and_the_note_of_what_was_wrong():
    output = points_verdict(
        False,
        [
            {"point": "Vieta's formulas", "ok": False, "note": "Sum and product swapped."},
            {"point": "Discriminant", "ok": True, "note": "ignored on a point that held"},
        ],
    )

    result, _ = next_turn(output, points=POINTS)

    assert result.passed is False
    assert result.points == [
        {"title": "Discriminant", "ok": True, "note": None},
        {"title": "Vieta's formulas", "ok": False, "note": "Sum and product swapped."},
    ]


def test_a_pass_with_a_point_marked_wrong_is_not_a_pass():
    output = points_verdict(True, [{"point": "Discriminant", "ok": True}, {"point": "Vieta's formulas", "ok": False}])

    result, _ = next_turn(output, points=POINTS)

    assert result.passed is False


def test_a_point_left_open_holds_on_a_pass_and_stays_open_on_a_fail():
    partial = [{"point": "Discriminant", "ok": True}]

    passed, _ = next_turn(points_verdict(True, partial), points=POINTS)
    failed, _ = next_turn(points_verdict(False, partial), points=POINTS)

    assert passed.passed is True and [p["ok"] for p in passed.points] == [True, True]
    assert [p["ok"] for p in failed.points] == [True, None]


def test_a_verdict_without_points_has_none_when_the_audit_has_none():
    result, _ = next_turn(verdict_json(True, 90))

    assert result.points is None


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
