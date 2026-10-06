"""Chat (contract section 5, endpoints 18-20): the front desk agent, the Mock rules, every intent,
the failure paths and the suggestions."""

import json

import pytest
from sqlmodel import Session, select

from app.agents.front_desk import FrontDesk, FrontDeskError
from app.llm.mock import MockProvider
from app.models import AuditSession, ChatMessage, Course, SkillStatus
from tests.helpers import (
    BrokenProvider,
    ScriptedProvider,
    fail_node,
    generate,
    ids_by_slug,
    make_course,
    make_skill,
    freeze_clock,
    pass_node,
)

VOICE = "I slept about six hours last night and didn't exercise. I had ramen for lunch and I'm a bit tired."


def use_provider(monkeypatch, provider):
    monkeypatch.setattr("app.routers.chat.get_provider", lambda agent=None: provider)
    return provider


def say(client, message: str) -> list[dict]:
    response = client.post("/api/chat", json={"message": message})
    assert response.status_code == 200, response.text
    return response.json()["messages"]


def front_desk_json(intent="none", args=None, reply="Sure."):
    return json.dumps({"intent": intent, "args": args or {}, "reply": reply}, ensure_ascii=False)


# ---------------------------------------------------------------- Mock front desk rules


def mock_route(message: str, titles=()) -> dict:
    result = FrontDesk(MockProvider()).route(message, list(titles))
    return {"intent": result.intent, "args": result.args, "reply": result.reply}


@pytest.mark.parametrize(
    "message, intent, args, reply",
    [
        ("I want to learn Math", "generate_course", {"topic": "Math"}, "I'll build a world for “Math”."),
        ("I'd like to learn Python.", "generate_course", {"topic": "Python"}, "I'll build a world for “Python”."),
        ("I want to study organic chemistry!", "generate_course", {"topic": "organic chemistry"}, "I'll build a world for “organic chemistry”."),
        ("Build me a world about guitar", "generate_course", {"topic": "guitar"}, "I'll build a world for “guitar”."),
        ("make a world for Linear Algebra", "generate_course", {"topic": "Linear Algebra"}, "I'll build a world for “Linear Algebra”."),
        ("Create a Spanish course", "generate_course", {"topic": "Create a Spanish course"}, "I'll build a world for “Create a Spanish course”."),
        ("I want to learn", "none", {}, "What topic should I build?"),
        ("I want to learn this.", "none", {}, "What topic should I build?"),
        ("i want to study these", "none", {}, "What topic should I build?"),
        ("Let me log my day", "checkin", {}, "Got it, logging that."),
        (VOICE, "checkin", {}, "Got it, logging that."),
        ("I had pasta for dinner", "checkin", {}, "Got it, logging that."),
        ("I worked out", "checkin", {}, "Got it, logging that."),
        ("What should I do today?", "plan", {}, "Let me pick today's quests."),
        ("Recommend something", "plan", {}, "Let me pick today's quests."),
        ("Show me today's quests", "plan", {}, "Let me pick today's quests."),
        ("Give me a status report", "briefing", {}, "Let me sum up where you are."),
        ("how am I doing?", "briefing", {}, "Let me sum up where you are."),
        ("Show me the map", "open_map", {}, "Opening your life tree."),
        ("take me to my world", "open_map", {}, "Opening your life tree."),
        ("Show my dex", "none", {}, "Sure. What would you like to do today?"),  # open_dex is gone
        ("Hello", "none", {}, "Sure. What would you like to do today?"),
        ("Create something", "generate_course", {"topic": "Create something"}, "I'll build a world for “Create something”."),
    ],
)
def test_mock_front_desk_rules(message, intent, args, reply):
    assert mock_route(message) == {"intent": intent, "args": args, "reply": reply}


@pytest.mark.parametrize(
    "message, topic",
    [
        ("I want to learn calculus", "calculus"),
        ("I WANT TO LEARN calculus", "calculus"),
        ("I'd like to learn calculus!!!", "calculus"),
        ("I’d like to learn calculus", "calculus"),
        ("I want to study calculus ?", "calculus"),
        ("Build me a world for calculus.", "calculus"),
        ("build me a world about calculus", "calculus"),
        ("Make a world for calculus", "calculus"),
        ("make a world about calculus...", "calculus"),
        ("Let's study calculus", "Let's study calculus"),  # only the listed leading phrases are stripped
    ],
)
def test_mock_front_desk_topic_stripping(message, topic):
    result = mock_route(message)

    assert result["intent"] == "generate_course"
    assert result["args"] == {"topic": topic}


def test_mock_front_desk_words_are_not_matched_inside_other_words():
    # "create" contains "ate" and "update" contains "date"; neither is a check-in.
    assert mock_route("Create a world for chess")["intent"] == "generate_course"
    assert mock_route("Update me")["intent"] == "none"


def test_mock_front_desk_open_skill_needs_a_node_title_and_an_open_word():
    titles = ["High School Math", "Quadratic Equations", "Discriminant"]

    assert mock_route("Let's try Quadratic Equations", titles) == {
        "intent": "open_skill",
        "args": {"skill": "Quadratic Equations"},
        "reply": "Taking you to “Quadratic Equations”.",
    }
    for word in ("challenge", "audit", "try", "open", "continue", "start"):
        assert mock_route(f"{word} discriminant", titles)["args"] == {"skill": "Discriminant"}, word
    # the title is matched case-insensitively and anywhere in the message
    assert mock_route("OPEN the discriminant, please", titles)["intent"] == "open_skill"
    # a title without an open word is not an open_skill
    assert mock_route("What are Quadratic Equations?", titles)["intent"] == "none"
    # an open word without a known title is not an open_skill
    assert mock_route("Challenge me on derivatives", titles)["intent"] == "none"


def test_mock_front_desk_open_skill_beats_the_other_rules_and_prefers_the_longest_title():
    titles = ["Math", "High School Math"]
    # "study" would be generate_course, but a title plus "challenge" is checked first
    assert mock_route("Challenge High School Math, then study", titles)["args"] == {"skill": "High School Math"}


def test_mock_front_desk_checkin_words_come_before_course_words():
    assert mock_route("I can't sleep, so I can't study")["intent"] == "checkin"


# ---------------------------------------------------------------- the agent's parsing


def route_with(raw):
    return FrontDesk(ScriptedProvider(front_desk=raw)).route("Hello", [])


def test_agent_prompt_carries_the_tag_and_the_node_titles():
    provider = ScriptedProvider(front_desk=front_desk_json())
    FrontDesk(provider).route("Open Quadratic Equations", ["Quadratic Equations", "Discriminant"])

    system = provider.system_prompts("front_desk")[0]
    assert system.startswith("[agent: front_desk]")
    assert "- Quadratic Equations\n- Discriminant" in system


def test_agent_parses_a_good_reply():
    result = route_with(front_desk_json("generate_course", {"topic": "Math"}, "On it."))

    assert (result.intent, result.args, result.reply) == ("generate_course", {"topic": "Math"}, "On it.")


@pytest.mark.parametrize(
    "raw",
    [
        "not json",
        "[]",
        json.dumps({"intent": "none"}),
        json.dumps({"intent": "none", "reply": ""}),
        json.dumps({"intent": "none", "reply": 3}),
        "",
    ],
)
def test_agent_rejects_unusable_output(raw):
    with pytest.raises(FrontDeskError):
        route_with(raw)


def test_agent_treats_an_unknown_intent_as_none_and_a_bad_args_as_empty():
    unknown = route_with(front_desk_json("start_audit", {"skill": "x"}, "Starting."))
    bad_args = route_with(json.dumps({"intent": "plan", "args": "oops", "reply": "Sure."}))

    assert (unknown.intent, unknown.args) == ("none", {})
    assert (bad_args.intent, bad_args.args) == ("plan", {})


def test_agent_retries_once_on_invalid_json():
    provider = ScriptedProvider(front_desk=["oops", front_desk_json("plan", reply="Picking.")])

    result = FrontDesk(provider).route("Recommend", [])

    assert result.intent == "plan"
    assert len(provider.calls_for("front_desk")) == 2


# ---------------------------------------------------------------- POST /api/chat, each intent


def test_none_intent_saves_the_user_message_and_one_reply(client):
    messages = say(client, "Hello")

    assert [m["role"] for m in messages] == ["user", "assistant"]
    assert messages[0]["content"] == "Hello" and messages[0]["agent"] is None and messages[0]["action"] is None
    assert messages[1] == {**messages[1], "content": "Sure. What would you like to do today?", "agent": "front_desk", "action": None}
    assert set(messages[1]) == {"id", "role", "content", "agent", "action", "created_at"}
    assert [m["id"] for m in messages] == sorted(m["id"] for m in messages)


def test_message_timestamps_carry_an_explicit_utc_offset(client):
    stamp = say(client, "Hello")[0]["created_at"]

    assert stamp.endswith("Z") or stamp.endswith("+00:00")


def test_generate_course_runs_the_default_generation(client, client_engine):
    messages = say(client, "I want to learn Math")

    assert [m["role"] for m in messages] == ["user", "assistant", "assistant"]
    assert messages[1]["content"] == "I'll build a world for “Math”." and messages[1]["agent"] == "front_desk"
    second = messages[2]
    assert second["agent"] == "planner"
    assert second["content"] == "Your world “High School Math” is ready — 12 nodes."
    action = second["action"]
    assert action["type"] == "course" and action["node_count"] == 12
    assert set(action["course"]) == {"id", "topic", "source_course", "source_url", "created_at"}
    assert action["course"]["topic"] == "Math"
    assert action["course"]["source_course"] == "High School Mathematics Curriculum (Ministry of Education)"  # the syllabus search ran
    assert client.get("/api/courses").json()[0]["id"] == action["course"]["id"]


def test_generate_course_for_another_topic_cuts_the_root_title(client):
    messages = say(client, "I want to learn cooking")

    assert messages[2]["content"] == "Your world “cooking” is ready — 10 nodes."
    assert messages[2]["action"]["node_count"] == 10


def test_generate_course_without_a_topic_only_asks(client, client_engine):
    messages = say(client, "I want to learn")

    assert [m["role"] for m in messages] == ["user", "assistant"]
    assert messages[1]["content"] == "What topic should I build?"
    with Session(client_engine) as session:
        assert session.exec(select(Course)).all() == []


def test_generate_course_with_a_blank_topic_from_the_model_runs_nothing(client, monkeypatch, client_engine):
    use_provider(monkeypatch, ScriptedProvider(front_desk=front_desk_json("generate_course", {"topic": "  "}, "What about?")))

    messages = say(client, "Let's make something")

    assert len(messages) == 2 and messages[1]["content"] == "What about?"
    with Session(client_engine) as session:
        assert session.exec(select(Course)).all() == []


def test_course_topic_builds_the_course_without_asking_the_front_desk(client, monkeypatch):
    # Even a front desk that would only small-talk cannot stop it: it is not called.
    spy = use_provider(monkeypatch, ScriptedProvider(front_desk=front_desk_json("none", reply="Hi!")))

    response = client.post("/api/chat", json={"message": "I want to learn Math", "course_topic": "Math"})

    messages = response.json()["messages"]
    assert [m["role"] for m in messages] == ["user", "assistant", "assistant"]
    assert messages[1]["content"] == "I'll build a world for “Math”."
    assert messages[2]["action"]["type"] == "course"
    assert spy.calls_for("front_desk") == []


def test_course_topic_with_only_a_file_takes_the_file_name(client, monkeypatch):
    spy = use_provider(monkeypatch, ScriptedProvider())
    upload = client.post("/api/uploads", files={"file": ("Linear Algebra.txt", b"Vectors and matrices", "text/plain")})

    response = client.post(
        "/api/chat",
        json={"message": "I want to learn this", "course_topic": "", "upload_ids": [upload.json()["id"]]},
    )

    messages = response.json()["messages"]
    assert messages[2]["action"]["course"]["topic"] == "Linear Algebra"
    assert messages[2]["action"]["course"]["source_course"] == "Linear Algebra.txt"
    assert spy.calls_for("front_desk") == [] and spy.calls_for("syllabus_finder") == []


def test_a_blank_course_topic_without_a_file_is_422(client, client_engine):
    response = client.post("/api/chat", json={"message": "I want to learn", "course_topic": "  "})

    assert response.status_code == 422
    with Session(client_engine) as session:
        assert session.exec(select(ChatMessage)).all() == []


def test_generate_course_failure_is_explained_with_200(client, monkeypatch, client_engine):
    use_provider(monkeypatch, ScriptedProvider(planner="not json at all"))

    messages = say(client, "I want to learn Math")

    assert len(messages) == 3
    assert messages[2]["agent"] == "front_desk" and messages[2]["action"] is None
    assert messages[2]["content"] == "I couldn't build that world. Please try again in a moment."
    with Session(client_engine) as session:
        assert session.exec(select(Course)).all() == []


def test_open_skill_puts_a_navigate_action_on_the_first_message(client):
    ids = ids_by_slug(generate(client, "Math"))

    messages = say(client, "Challenge Quadratic Equations")

    assert len(messages) == 2
    assert messages[1]["content"] == "Taking you to “Quadratic Equations”."
    assert messages[1]["action"] == {"type": "navigate", "scene": "skill", "skill_id": ids["quadratic-equation"]}


def test_open_skill_resolves_exact_before_contains_and_newest_course_first(client, monkeypatch):
    older = ids_by_slug(generate(client, "Math"))
    newer = ids_by_slug(generate(client, "Math"))
    assert older["algebra"] != newer["algebra"]

    def skill_of(text):
        use_provider(monkeypatch, ScriptedProvider(front_desk=front_desk_json("open_skill", {"skill": text}, "Going.")))
        return say(client, "Open it")[1]["action"]["skill_id"]

    assert skill_of("Quadratic Equations") == newer["quadratic-equation"]  # newest course first
    assert skill_of("Equations") == newer["quadratic-equation"]  # a title that contains the text
    assert skill_of("Roots and Coefficients") == newer["root-coefficient"]
    assert skill_of("please open Quadratic Equations now") == newer["quadratic-equation"]  # the text contains a title
    # exact beats contains: "Sequences" (exact) over "Limits of Sequences" (contains)
    assert skill_of("Sequences") == newer["sequences"]


def test_open_skill_not_found_asks_which_node(client, monkeypatch):
    generate(client, "Math")
    use_provider(monkeypatch, ScriptedProvider(front_desk=front_desk_json("open_skill", {"skill": "Quantum Mechanics"}, "Going.")))

    messages = say(client, "Open quantum mechanics")

    assert len(messages) == 2 and messages[1]["action"] is None
    assert messages[1]["content"] == "Which node do you mean? Tell me its name."


def test_checkin_runs_the_converter_on_the_message(client):
    messages = say(client, VOICE)

    assert [m["role"] for m in messages] == ["user", "assistant", "assistant"]
    second = messages[2]
    assert second["agent"] == "checkin_converter"
    assert second["content"] == "Logged: sleep 6 h · exercise no · meals lunch: ramen"
    assert second["action"]["type"] == "checkin"
    result = second["action"]["result"]
    assert result["checkin"]["sleep_hours"] == 6 and result["checkin"]["source"] == "voice"
    assert result["checkin"]["transcript"] == VOICE
    assert result["missing_fields"] == ["focus", "stress"]
    assert client.get("/api/checkins/today").json()["sleep_hours"] == 6


def test_checkin_with_nothing_recognised_says_so_and_still_records(client):
    messages = say(client, "I'm so tired today")

    assert messages[2]["agent"] == "checkin_converter"
    assert messages[2]["content"] == "I couldn't find anything to log. Tell me about sleep, exercise or meals."
    assert messages[2]["action"]["result"]["missing_fields"] == [
        "sleep_hours", "exercised", "diet_note", "focus", "stress",
    ]


def test_checkin_converter_failure_is_not_an_error(client, monkeypatch):
    use_provider(monkeypatch, ScriptedProvider(checkin_converter="garbage"))

    messages = say(client, VOICE)

    assert messages[2]["action"]["result"]["checkin"]["sleep_hours"] is None


def test_checkin_in_chat_replaces_the_day_record(client):
    say(client, VOICE)
    say(client, "I slept eight hours")

    today = client.get("/api/checkins/today").json()
    assert today["sleep_hours"] == 8 and today["diet_note"] is None


def test_plan_runs_the_recommender(client):
    generate(client, "Math")

    messages = say(client, "What should I do today?")

    assert len(messages) == 3
    second = messages[2]
    assert second["agent"] == "recommender"
    assert second["action"]["type"] == "plan"
    plan = second["action"]["plan"]
    assert plan["id"] == client.get("/api/plan/current").json()["id"]
    assert [s["skill_title"] for s in plan["steps"]] == ["High School Math"]
    assert second["content"] == "Today's quests: “High School Math”."


def test_plan_without_an_available_node_is_explained_with_200(client):
    messages = say(client, "What should I do today?")

    assert len(messages) == 3
    assert messages[2]["agent"] == "front_desk" and messages[2]["action"] is None
    assert messages[2]["content"] == "No node is ready yet. Make a world first."
    assert client.get("/api/plan/current").json() is None


def test_plan_failure_is_explained_with_200(client, monkeypatch):
    generate(client, "Math")
    use_provider(monkeypatch, ScriptedProvider(recommender="garbage"))

    messages = say(client, "Recommend something")

    assert messages[2]["agent"] == "front_desk" and messages[2]["action"] is None
    assert messages[2]["content"] == "I couldn't pick today's quests. Please try again."
    assert client.get("/api/plan/current").json() is None


def test_briefing_narrates(client):
    generate(client, "Math")

    messages = say(client, "Give me a status report")

    second = messages[2]
    assert second["agent"] == "narrator"
    assert second["content"] == client.get("/api/narrator/briefing").json()["narrative"]
    assert second["content"].startswith("You've cleared 0 of 12 nodes.")
    assert second["action"]["type"] == "briefing"
    assert second["action"]["briefing"]["narrative"] == second["content"]
    assert second["action"]["briefing"]["facts"]["xp"] == {"total": 0, "level": 1, "level_progress": 0.0}


def test_briefing_failure_is_explained_with_200(client, monkeypatch):
    use_provider(monkeypatch, ScriptedProvider(narrator="garbage"))

    messages = say(client, "Give me a status report")

    assert messages[2]["agent"] == "front_desk" and messages[2]["action"] is None
    assert messages[2]["content"] == "I couldn't put your status together. Please try again."
    assert client.get("/api/narrator/briefing").json()["narrative"] is None


def test_open_map_navigates_without_a_second_message(client):
    messages = say(client, "Show me the map")

    assert len(messages) == 2
    assert messages[1]["content"] == "Opening your life tree."
    assert messages[1]["action"] == {"type": "navigate", "scene": "map"}


def test_open_dex_is_no_longer_an_intent(client, monkeypatch):
    use_provider(monkeypatch, ScriptedProvider(front_desk=front_desk_json("open_dex", {}, "Opening the dex.")))

    messages = say(client, "Show my dex")

    assert len(messages) == 2 and messages[1]["action"] is None
    assert messages[1]["content"] == "Opening the dex."  # an unknown intent keeps the reply and runs nothing


def test_audits_never_start_from_chat(client, monkeypatch, client_engine):
    generate(client, "Math")
    use_provider(monkeypatch, ScriptedProvider(front_desk=front_desk_json("start_audit", {"skill": "Algebra"}, "Starting.")))

    messages = say(client, "Audit me on Algebra")

    assert len(messages) == 2 and messages[1]["action"] is None
    with Session(client_engine) as session:
        assert session.exec(select(AuditSession)).all() == []


# ---------------------------------------------------------------- failures of the front desk


@pytest.mark.parametrize("provider", [BrokenProvider(), ScriptedProvider(front_desk="not json")])
def test_front_desk_failure_is_a_502_and_keeps_the_user_message(client, monkeypatch, provider):
    use_provider(monkeypatch, provider)

    response = client.post("/api/chat", json={"message": "Hello"})

    assert response.status_code == 502
    assert response.json() == {"detail": "The assistant is temporarily unavailable. Please try again."}
    history = client.get("/api/chat/history").json()
    assert [(m["role"], m["content"]) for m in history] == [("user", "Hello")]


def test_front_desk_failure_runs_no_pipeline(client, monkeypatch, client_engine):
    use_provider(monkeypatch, ScriptedProvider(front_desk="oops"))

    assert client.post("/api/chat", json={"message": "I want to learn Math"}).status_code == 502

    with Session(client_engine) as session:
        assert session.exec(select(Course)).all() == []


def test_provider_construction_failure_is_also_a_502(client, monkeypatch):
    def boom(agent=None):
        raise RuntimeError("no key")

    monkeypatch.setattr("app.routers.chat.get_provider", boom)

    assert client.post("/api/chat", json={"message": "Hello"}).status_code == 502


@pytest.mark.parametrize("body", [{"message": ""}, {"message": "   "}, {}])
def test_blank_or_missing_message_is_422_and_nothing_is_saved(client, body):
    assert client.post("/api/chat", json=body).status_code == 422
    assert client.get("/api/chat/history").json() == []


def test_the_front_desk_is_asked_for_its_own_model(client, monkeypatch):
    requested = []
    provider = ScriptedProvider()
    monkeypatch.setattr("app.routers.chat.get_provider", lambda agent=None: (requested.append(agent), provider)[1])

    say(client, "I want to learn Math")

    assert requested[0] == "front_desk"
    assert {"planner", "syllabus_finder"} <= set(requested)


# ---------------------------------------------------------------- history


def test_history_is_oldest_first_and_limited_to_the_last_n(client):
    say(client, "Hello")  # ids 1, 2
    say(client, "Show me the map")  # ids 3, 4

    everything = client.get("/api/chat/history").json()
    assert [m["id"] for m in everything] == [1, 2, 3, 4]
    assert [m["content"] for m in everything][::2] == ["Hello", "Show me the map"]

    last_two = client.get("/api/chat/history?limit=2").json()
    assert [m["id"] for m in last_two] == [3, 4]
    assert client.get("/api/chat/history?limit=1").json()[0]["id"] == 4


def test_history_keeps_actions_and_agents(client):
    say(client, VOICE)

    history = client.get("/api/chat/history").json()

    assert [m["agent"] for m in history] == [None, "front_desk", "checkin_converter"]
    assert history[2]["action"]["type"] == "checkin"


def test_history_is_empty_at_first(client):
    assert client.get("/api/chat/history").json() == []


@pytest.mark.parametrize("limit", [0, 201, -1, "x"])
def test_history_limit_out_of_range_is_422(client, limit):
    assert client.get(f"/api/chat/history?limit={limit}").status_code == 422


def test_history_accepts_the_range_edges(client):
    assert client.get("/api/chat/history?limit=1").status_code == 200
    assert client.get("/api/chat/history?limit=200").status_code == 200


def test_chat_rows_survive_in_the_database(client, client_engine):
    say(client, "Hello")

    with Session(client_engine) as session:
        rows = session.exec(select(ChatMessage).order_by(ChatMessage.id)).all()
    assert [(r.role, r.agent) for r in rows] == [("user", None), ("assistant", "front_desk")]


# ---------------------------------------------------------------- suggestions


def suggestions(client) -> list[dict]:
    response = client.get("/api/chat/suggestions")
    assert response.status_code == 200
    return response.json()["suggestions"]


def labels(client) -> list[str]:
    return [s["label"] for s in suggestions(client)]


CHECKIN_CHIP = {"label": "How was your day?", "message": "Let me log my day", "skill_id": None, "reflection": False}
NO_COURSE_CHIP = {"label": "Tell me what you want to learn", "message": "", "skill_id": None, "reflection": False}
NOON_REFLECTION = "What are you putting off right now?"  # the 11:00-13:29 window


def test_no_course_suggests_the_checkin_then_asks_what_to_learn(client):
    assert suggestions(client) == [CHECKIN_CHIP, NO_COURSE_CHIP]


def test_no_course_with_a_checkin_today_swaps_the_checkin_chip_for_the_reflection(client, monkeypatch):
    freeze_clock(monkeypatch, "2026-10-05 12:00")
    client.post("/api/checkins", json={"sleep_hours": 7})

    assert suggestions(client) == [
        {"label": NOON_REFLECTION, "message": "", "skill_id": None, "reflection": True},
        NO_COURSE_CHIP,
    ]


def test_a_fresh_course_suggests_the_checkin_and_starting_the_root(client):
    ids = ids_by_slug(generate(client, "Math"))

    assert suggestions(client) == [
        CHECKIN_CHIP,
        {"label": "Start with “High School Math”", "message": "Start with “High School Math”",
         "skill_id": ids["high-school-math"], "reflection": False},
    ]


def test_with_a_checkin_today_the_checkin_chip_becomes_the_reflection(client, monkeypatch):
    freeze_clock(monkeypatch, "2026-10-05 12:00")
    generate(client, "Math")
    client.post("/api/checkins", json={"sleep_hours": 7})

    assert labels(client) == [NOON_REFLECTION, "Start with “High School Math”"]


def test_a_failed_unmastered_audit_node_is_continued(client):
    ids = ids_by_slug(generate(client, "Math"))
    pass_node(client, ids["high-school-math"])
    fail_node(client, ids["algebra"])

    items = suggestions(client)

    assert [s["label"] for s in items] == ["How was your day?", "Continue “Algebra”"]
    assert items[1]["skill_id"] == ids["algebra"]


def test_only_the_most_recent_audit_decides(client):
    ids = ids_by_slug(generate(client, "Math"))
    pass_node(client, ids["high-school-math"])
    fail_node(client, ids["algebra"])
    fail_node(client, ids["functions"])

    assert suggestions(client)[1]["label"] == "Continue “Functions”"


def test_when_the_latest_audit_node_is_mastered_the_course_start_is_offered(client):
    ids = ids_by_slug(generate(client, "Math"))
    pass_node(client, ids["high-school-math"])
    fail_node(client, ids["algebra"])
    pass_node(client, ids["algebra"])  # the most recent audit is now on a mastered node

    item = suggestions(client)[1]

    assert item["label"].startswith("Start with “")
    assert item["skill_id"] not in (ids["high-school-math"], ids["algebra"])  # an available, not-yet-mastered node


def test_start_node_is_the_lowest_available_id_of_the_newest_course(client):
    generate(client, "Math")
    ids = ids_by_slug(generate(client, "Cooking"))

    item = suggestions(client)[1]

    assert item == {"label": "Start with “Cooking”", "message": "Start with “Cooking”", "skill_id": ids["root"], "reflection": False}


def test_never_more_than_two_suggestions(client, monkeypatch):
    freeze_clock(monkeypatch, "2026-10-05 12:00")
    ids = ids_by_slug(generate(client, "Math"))
    pass_node(client, ids["high-school-math"])
    fail_node(client, ids["algebra"])

    assert len(suggestions(client)) == 2

    client.post("/api/checkins", json={"sleep_hours": 7})
    assert len(suggestions(client)) == 2  # the reflection replaces the check-in chip


def test_a_course_with_nothing_available_asks_what_to_learn(client, client_engine, monkeypatch):
    freeze_clock(monkeypatch, "2026-10-05 12:00")
    with Session(client_engine) as session:
        course = make_course(session)
        make_skill(session, course, "done", status=SkillStatus.mastered)
    client.post("/api/checkins", json={"sleep_hours": 7})

    assert labels(client) == [NOON_REFLECTION, "Tell me what you want to learn"]


def test_suggestion_shape(client):
    generate(client, "Math")

    assert all(set(s) == {"label", "message", "skill_id", "reflection"} for s in suggestions(client))
