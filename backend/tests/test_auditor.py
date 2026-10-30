"""Auditor：点评 + 追问 / 裁决的解析、知识点、位置块、pacing、轮数上限（UT-06 ~ UT-11）。"""

import json
from types import SimpleNamespace

import pytest

from app.agents.auditor import (
    FINAL_TURN_LINE,
    GENERIC_PROBE,
    Auditor,
    AuditorOutputError,
    _within,
    asked_so_far,
    began_with,
    format_lessons,
    gap_evidence,
    lesson_checks,
    said_by_user,
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
    assert "Details one would look up while doing it" in prompt
    assert "Brevity is not a gap." in prompt
    assert "At most three\n  gaps" in prompt
    assert "on the final turn, give the benefit of the doubt" in prompt


def test_a_wrong_claim_is_a_gap_only_once_it_was_put_to_the_user():
    """Production audits were failed on claims the conversation never raised, two of them right."""
    _, provider = next_turn(probe_json())
    prompt = system_prompt(provider)

    assert "a claim that stayed wrong after its second try" in prompt
    assert "an answer to the\n  last question that is wrong in substance" in prompt
    assert "a wrong claim that was never put to them is not a gap" in prompt
    assert "never holds against them something the conversation did not\n  raise" in prompt
    assert "do not give the verdict: ask about\n  it." in prompt
    assert "name it in the comment as what to check" in prompt
    assert "even if you never asked about it" not in prompt
    assert "pass is true when there is no gap" in prompt


def test_loose_wording_and_misheard_words_are_judged_by_what_was_meant():
    _, provider = next_turn(probe_json())
    prompt = system_prompt(provider)

    assert "Wrong means wrong in substance" in prompt
    assert "A loose, shortened or\n  everyday way of saying something right is right" in prompt
    assert "speech recognition" in prompt
    assert "what they said, not what it resembles" in prompt


def test_a_task_passes_on_the_actions_said_not_on_a_report_that_it_is_done():
    """An audit passed at 95 on "I already did all of it"."""
    _, provider = next_turn(probe_json(), node_type=NodeType.task)
    prompt = system_prompt(provider)

    assert "tells you the result and not the actions" in prompt
    assert "ask what they did" in prompt
    assert "vouches for the routine actions it could not have been reached without" in prompt
    assert 'would do "somehow" is not known' in prompt
    assert "a setting they would look up while doing it, which is not required" in prompt


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


def test_the_rules_keep_her_at_the_level_of_the_point_and_hold_nothing_unasked():
    _, provider = next_turn(probe_json(), points=POINTS)
    prompt = system_prompt(provider)

    assert "Never go a level below that" in prompt and "splitting hairs" in prompt
    assert "you asked them for and their answers\n  still did not give" in prompt
    assert "neither is a part nobody asked them about" in prompt
    assert "their own words never reached" not in prompt
    assert "a question they could not make sense of is not held" in prompt


def test_she_is_shown_her_own_questions_once_there_are_two_and_told_a_part_gets_two():
    _, two_asked = next_turn(probe_json(), user_turns=3)
    _, one_asked = next_turn(probe_json(), user_turns=2)

    assert "Your questions so far, in order:\n1. Question 1\n2. Question 2\n" in system_prompt(two_asked)
    assert "A narrower question on the same part" in system_prompt(two_asked)
    assert "Your questions so far" not in system_prompt(one_asked)


def test_her_questions_are_listed_without_the_feedback_before_them():
    messages = [
        {"role": "assistant", "content": "Explain it from scratch."},
        {"role": "user", "content": "a"},
        {"role": "assistant", "content": "I follow the first step.\n\nWhy the sign?"},
        {"role": "user", "content": "b"},
    ]

    assert asked_so_far(messages) == ["Why the sign?"]


def test_closed_points_are_named_and_all_of_them_closed_makes_the_turn_final():
    _, some = next_turn(probe_json(), points=POINTS, closed=["Discriminant"])
    forced, every = next_turn(probe_json(), points=POINTS, closed=[p["title"] for p in POINTS])

    assert "judge them on what was said: Discriminant\n" in system_prompt(some)
    assert "give the verdict now" not in system_prompt(some)
    assert "give the verdict now" in system_prompt(every)
    assert forced.is_verdict is True and forced.passed is False


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


# ---------------------------------------------------------------- evidence and lesson checks


def evidence_verdict(gaps, evidence=None, lessons=None) -> str:
    data = {"action": "verdict", "pass": False, "score": 40, "gaps": gaps, "comment": "c"}
    if evidence is not None:
        data["evidence"] = evidence
    if lessons is not None:
        data["lessons"] = lessons
    return json.dumps(data, ensure_ascii=False)


def spoken(*user_texts: str) -> list[dict]:
    messages = [{"role": "assistant", "content": "Explain it from scratch."}]
    for text in user_texts:
        messages += [{"role": "user", "content": text}, {"role": "assistant", "content": "And then?"}]
    return messages


def test_the_prompt_asks_for_evidence_and_for_a_check_on_each_lesson_that_came_up():
    _, provider = next_turn(probe_json())

    prompt = system_prompt(provider)
    assert '"evidence" has one entry for each gap' in prompt
    assert "copied exactly from one of their answers" in prompt
    assert '"lessons": for each past lesson above whose situation came up' in prompt


def test_a_quote_found_in_a_user_turn_is_kept():
    assert said_by_user("no real roots", spoken("I think no real roots means no solutions")) == "no real roots"


def test_a_quote_is_matched_without_regard_to_spacing_or_case():
    history = spoken("I think  No Real\nRoots means nothing")

    assert said_by_user("no real roots", history) == "no real roots"


def test_a_quote_wrapped_in_quote_marks_is_kept_without_them():
    history = spoken("I think no real roots means no solutions")

    assert said_by_user("“no real roots”", history) == "no real roots"
    assert said_by_user('"no real roots"', history) == "no real roots"


def test_a_quote_that_only_the_assistant_said_is_dropped():
    history = spoken("I think it is about roots")
    history[0]["content"] = "Tell me about the repeated root"

    assert said_by_user("the repeated root", history) is None


def test_a_reworded_empty_or_non_string_quote_is_dropped():
    history = spoken("I think no real roots means no solutions")

    assert said_by_user("no complex roots means no solutions", history) is None
    assert said_by_user("", history) is None
    assert said_by_user("   ", history) is None
    assert said_by_user(None, history) is None
    assert said_by_user(42, history) is None
    assert said_by_user(["no real roots"], history) is None


def test_a_verdict_has_one_evidence_entry_per_gap_in_order():
    output = evidence_verdict(
        ["Skipped why", "Missed the repeated root"],
        [{"said": "it just works", "right": "Each step follows from the last."}, {"said": "the root is single", "right": "A double root is one value."}],
    )

    result, _ = next_turn_with_history(output, spoken("well it just works", "I think the root is single"))

    assert result.evidence == [
        {"gap": "Skipped why", "said": "it just works", "right": "Each step follows from the last."},
        {"gap": "Missed the repeated root", "said": "the root is single", "right": "A double root is one value."},
    ]


def next_turn_with_history(output: str, messages: list[dict], **kwargs):
    provider = ScriptedProvider(auditor=output)
    result = Auditor(provider).next_turn("Quadratic Equations", "Judge the roots with the discriminant", messages, **kwargs)
    return result, provider


def test_evidence_whose_said_is_not_the_users_words_keeps_right_and_drops_said():
    output = evidence_verdict(["Skipped why"], [{"said": "I memorised the formula", "right": "Say why it holds."}])

    result, _ = next_turn(output)

    assert result.evidence == [{"gap": "Skipped why", "said": None, "right": "Say why it holds."}]


@pytest.mark.parametrize(
    "evidence",
    [None, "not a list", {"said": "x"}, [], ["a string", 3], [{"right": "Only the first."}]],
    ids=["missing", "string", "dict", "empty", "non-dicts", "short"],
)
def test_missing_short_or_malformed_evidence_still_gives_one_entry_per_gap(evidence):
    result, _ = next_turn(evidence_verdict(["First gap", "Second gap"], evidence))

    assert [e["gap"] for e in result.evidence] == ["First gap", "Second gap"]
    assert all(set(e) == {"gap", "said", "right"} and e["said"] is None for e in result.evidence)
    assert result.evidence[1]["right"] is None


def test_gap_evidence_keeps_the_gap_order_when_the_model_gave_more_entries_than_gaps():
    evidence = gap_evidence([{"right": "One"}, {"right": "Two"}], ["Only gap"], spoken("x"))

    assert evidence == [
        {"gap": "Only gap", "said": None, "asked": None, "named": None, "right": "One", "kind": None, "point": None}
    ]


# ---------------------------------------------------------------- gaps that were never raised


def kinds_verdict(*entries, points=None) -> str:
    data = json.loads(evidence_verdict([e["gap"] for e in entries], list(entries)))
    if points is not None:
        data["points"] = points
    return json.dumps(data)


@pytest.mark.parametrize("kind", ["partial", "unasked", "detail", "Detail"])
def test_a_gap_she_calls_not_raised_is_dropped_and_a_fail_with_none_left_is_a_pass(kind):
    result, _ = next_turn(kinds_verdict({"gap": "Which patch gets which vector", "kind": kind, "right": "r"}))

    assert result.gaps == [] and result.evidence == []
    assert result.passed is True


def test_a_not_given_gap_stands_only_with_the_question_that_asked_for_it():
    asked = history(1)[0]["content"]
    with_question, _ = next_turn(kinds_verdict({"gap": "G", "kind": "not_given", "asked": asked, "named": "scratch"}))
    without, _ = next_turn(
        kinds_verdict({"gap": "G", "kind": "not_given", "asked": "Something I never asked", "named": "never"})
    )

    assert with_question.gaps == ["G"] and with_question.passed is False
    assert without.gaps == [] and without.passed is True


@pytest.mark.parametrize("named", [None, "", "how the decoder uses the encoder's output", 42])
def test_a_not_given_gap_whose_question_has_no_words_naming_what_is_missing_is_dropped(named):
    # Audit 36: "what do the encoder and the decoder each do?" answered right, then held against
    # the user for how the decoder uses the encoder's output, which the question never named.
    messages = [
        {"role": "assistant", "content": "What do the encoder and the decoder each do?"},
        {"role": "user", "content": "The encoder compresses the input, the decoder generates."},
    ]
    entry = {"gap": "How the decoder uses the encoder's output", "kind": "not_given", "point": None}
    entry.update(asked="What do the encoder and the decoder each do?", named=named)

    result, _ = next_turn_with_history(kinds_verdict(entry), messages, max_turns=1)

    assert result.gaps == [] and result.passed is True


def test_a_not_given_gap_stands_when_its_question_named_the_missing_thing():
    messages = [
        {"role": "assistant", "content": "How does the decoder use what the encoder gives it?"},
        {"role": "user", "content": "It just generates the next word."},
    ]
    entry = {"gap": "How the decoder uses the encoder's output", "kind": "not_given"}
    entry.update(asked="How does the decoder use what the encoder gives it?", named="“use what the encoder gives it”")

    result, _ = next_turn_with_history(kinds_verdict(entry), messages, max_turns=1)

    assert result.gaps == ["How the decoder uses the encoder's output"] and result.passed is False


def test_the_naming_words_are_checked_against_the_question_and_kept_as_quoted():
    assert _within("Each DO", "What do A and B each do?") == "Each DO"
    assert _within("“each do”", "What do A and B each do?") == "each do"
    assert _within("how B uses A", "What do A and B each do?") is None
    assert _within("x", "What do A and B each do?") is None
    assert _within("each do", None) is None


def test_the_prompt_asks_for_the_words_that_name_what_is_missing():
    _, provider = next_turn(verdict_json(True))

    prompt = system_prompt(provider)
    assert '"named"' in prompt
    assert "what do A and B each do?" in prompt


def test_gaps_of_the_other_kinds_or_of_no_kind_stand():
    result, _ = next_turn(
        kinds_verdict({"gap": "A", "kind": "wrong_twice"}, {"gap": "B", "kind": "detail"}, {"gap": "C"})
    )

    assert result.gaps == ["A", "C"]
    assert [e["gap"] for e in result.evidence] == ["A", "C"]
    assert result.passed is False


def test_a_point_marked_wrong_only_for_a_dropped_gap_stays_open_and_keeps_the_audit_from_passing():
    titles = [p["title"] for p in POINTS]
    marks = [{"point": titles[0], "ok": True}, {"point": titles[1], "ok": False, "note": "Did not say how."}]
    result, _ = next_turn(
        kinds_verdict({"gap": "How", "kind": "unasked", "point": titles[1]}, points=marks), points=POINTS
    )

    assert result.gaps == []
    assert result.points == [
        {"title": titles[0], "ok": True, "note": None},
        {"title": titles[1], "ok": None, "note": None},
    ]
    assert result.passed is False  # not settled is not passed; nothing is held against them


def test_a_point_with_a_gap_that_stands_stays_wrong_when_another_of_its_gaps_is_dropped():
    titles = [p["title"] for p in POINTS]
    marks = [{"point": titles[0], "ok": True}, {"point": titles[1], "ok": False, "note": "Signs."}]
    result, _ = next_turn(
        kinds_verdict(
            {"gap": "Signs", "kind": "wrong_twice", "point": titles[1]},
            {"gap": "Order", "kind": "detail", "point": titles[1]},
            points=marks,
        ),
        points=POINTS,
    )

    assert result.gaps == ["Signs"]
    assert result.points[1] == {"title": titles[1], "ok": False, "note": "Signs."}


def test_lesson_checks_are_numbered_from_one_into_the_lessons_given():
    raw = [{"lesson": 2, "held": True}, {"lesson": 1, "held": False}]

    assert lesson_checks(raw, 3) == [{"index": 0, "held": False}, {"index": 1, "held": True}]


def test_lesson_checks_ignore_out_of_range_duplicate_and_non_bool_entries():
    raw = [
        {"lesson": 0, "held": True},
        {"lesson": 4, "held": True},
        {"lesson": -1, "held": True},
        {"lesson": 1, "held": True},
        {"lesson": 1, "held": False},  # a second word on the same lesson
        {"lesson": 2, "held": "yes"},
        {"lesson": 2, "held": 1},
        {"lesson": "x", "held": True},
        "junk",
    ]

    assert lesson_checks(raw, 3) == [{"index": 0, "held": True}]


def test_lesson_checks_ignore_input_that_is_not_a_list():
    assert lesson_checks(None, 2) == []
    assert lesson_checks({"lesson": 1, "held": True}, 2) == []
    assert lesson_checks("1", 2) == []


def test_with_no_lessons_given_there_are_no_lesson_checks():
    assert lesson_checks([{"lesson": 1, "held": True}], 0) == []

    result, _ = next_turn(evidence_verdict([], lessons=[{"lesson": 1, "held": True}]))

    assert result.lesson_checks == []


def test_a_verdict_reports_the_lessons_that_held_and_the_ones_that_came_back():
    output = evidence_verdict(["g"], lessons=[{"lesson": 1, "held": False}, {"lesson": 2, "held": True}])

    result, _ = next_turn(output, lessons=[lesson("A"), lesson("B")])

    assert result.lesson_checks == [{"index": 0, "held": False}, {"index": 1, "held": True}]


def test_a_quote_she_ended_with_her_own_punctuation_is_still_the_users_words():
    """Speech comes without full stops; she adds one, and the quote was dropped for it."""
    history = [{"role": "assistant", "content": "Q"}, {"role": "user", "content": "每层接入的特征都有更多的 global feature 然后再往下走"}]

    assert said_by_user("每层接入的特征都有更多的 global feature。", history) == "每层接入的特征都有更多的 global feature"
    assert said_by_user("“每层接入的特征都有更多的 global feature，”", history) == "每层接入的特征都有更多的 global feature"
