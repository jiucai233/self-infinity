"""Course Scout: the tutorial's first course is read next to the player's quest before it is built."""

import json

from app.agents.course_scout import CourseScout, PlayerContext
from tests.helpers import BrokenProvider, ScriptedProvider


def scout_output(**data) -> str:
    return json.dumps(data, ensure_ascii=False)


CONTEXT = PlayerContext(main_quests=["Complete SO-ARM101 project"], win_condition="In KAIST CLVR")


def test_a_clear_answer_comes_back_as_a_tidy_title():
    provider = ScriptedProvider(course_scout=scout_output(kind="clear", topic="  SO-ARM101   robot arm "))

    result = CourseScout(provider).scout("so arm 101", CONTEXT)

    assert (result.kind, result.topic) == ("clear", "SO-ARM101 robot arm")


def test_a_vague_answer_comes_back_as_at_most_three_distinct_options():
    options = [{"topic": t, "why": "because"} for t in ["Robot learning", "robot learning", "ROS 2", "PyTorch", "C++"]]
    provider = ScriptedProvider(course_scout=scout_output(kind="choose", question="Pick one:", options=options))

    result = CourseScout(provider).scout("idk, a lot of things", CONTEXT)

    assert result.kind == "choose"
    assert result.question == "Pick one:"
    assert [o.topic for o in result.options] == ["Robot learning", "ROS 2", "PyTorch"]


def test_the_model_sees_the_quest_the_profile_and_the_answer_last():
    provider = ScriptedProvider(course_scout=scout_output(kind="clear", topic="X"))

    CourseScout(provider).scout("idk", CONTEXT)

    (messages,) = provider.calls_for("course_scout")
    brief = messages[-1]["content"]
    assert "Main quest: Complete SO-ARM101 project" in brief
    assert "Win condition: In KAIST CLVR" in brief
    assert brief.splitlines()[-1] == "Answer: idk"


def test_anything_unusable_means_build_what_was_typed():
    typed = "so arm 101"
    for provider in [
        BrokenProvider(),
        ScriptedProvider(course_scout="not json"),
        ScriptedProvider(course_scout=scout_output(kind="choose", options=[])),
        ScriptedProvider(course_scout=scout_output(kind="clear", topic="  ")),
        ScriptedProvider(course_scout=scout_output(kind="maybe")),
    ]:
        result = CourseScout(provider).scout(typed, CONTEXT)
        assert (result.kind, result.topic, result.options) == ("clear", typed, [])


# ---------------------------------------------------------------- the endpoint, on the Mock script


def test_endpoint_offers_courses_from_the_main_quest_for_a_vague_answer(client):
    client.post("/api/goals", json={"title": "Complete SO-ARM101 project"})

    body = client.post("/api/skills/scout", json={"answer": "idk, a lot of things"}).json()

    assert body["kind"] == "choose"
    assert len(body["options"]) == 3
    assert body["options"][0]["topic"] == "SO-ARM101 project"


def test_endpoint_passes_a_clear_answer_through(client):
    body = client.post("/api/skills/scout", json={"answer": "Linear algebra"}).json()

    assert body == {"kind": "clear", "topic": "Linear algebra", "question": "", "options": []}


def test_endpoint_rejects_a_blank_answer(client):
    assert client.post("/api/skills/scout", json={"answer": "  "}).status_code == 422
