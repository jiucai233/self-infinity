"""The Guide (app/agents/guide.py): a chat message routed to `none` is answered with the chat so
far, older related lines, today's check-in and what the game knows; a logged check-in gets one
line on what it changes today. The router sees the recent chat too."""

import json

from sqlmodel import Session

from app.agents.front_desk import FrontDesk
from app.config import settings
from app.llm import decisions
from app.models import AuditStatus, ChatMessage, FactCategory, LifeFact
from app.services import chat as chat_service
from tests.helpers import ScriptedProvider, make_audit, make_course, make_skill
from tests.test_front_desk_decisions import deciding

ATE = "I slept 7 hours. I had a sausage roll and ice cream for lunch."


def desk(intent="none", reply="Sure.", args=None):
    return json.dumps({"intent": intent, "args": args or {}, "reply": reply}, ensure_ascii=False)


def use(monkeypatch, provider):
    monkeypatch.setattr("app.routers.chat.get_provider", lambda agent=None: provider)
    return provider


def say(client, message, language=None):
    headers = {"Accept-Language": language} if language else {}
    response = client.post("/api/chat", json={"message": message}, headers=headers)
    assert response.status_code == 200, response.text
    return response.json()["messages"]


def broken(messages):
    raise RuntimeError("provider down")


# ---------------------------------------------------------------- the chat reaches the router


def test_the_llm_router_and_the_guide_see_the_chat_so_far(client, monkeypatch):
    provider = use(monkeypatch, ScriptedProvider(
        front_desk=desk(), guide=[json.dumps({"reply": "Which food do you mean?"}), json.dumps({"reply": "Ok."})],
    ))

    say(client, "多少卡?")
    say(client, "我说我今天吃的")

    router = provider.system_prompts("front_desk")[-1]
    recent = router.split("<recent>")[1].split("</recent>")[0]
    assert "User: 多少卡?" in recent and "Guide: Which food do you mean?" in recent
    assert "我说我今天吃的" not in recent  # the message itself is the user turn, not context
    guide = provider.system_prompts("guide")[-1]
    assert "User: 多少卡?\nGuide: Which food do you mean?" in guide
    assert provider.calls_for("guide")[-1][-1]["content"] == "我说我今天吃的"


def test_the_router_sees_at_most_the_last_six_lines():
    provider = ScriptedProvider(front_desk=desk())
    turns = [("User", f"line {i}") for i in range(10)]

    FrontDesk(provider).route("next", [], turns)

    prompt = provider.system_prompts("front_desk")[0]
    assert "line 3" not in prompt and "line 4" in prompt and "line 9" in prompt


def test_the_fast_path_reads_the_recent_lines_too(client, monkeypatch):
    use(monkeypatch, ScriptedProvider(front_desk=desk("plan", "Picking.")))
    say(client, "多少卡?")
    monkeypatch.setattr(settings, "openai_api_key", "sk-test")
    decide = deciding("plan")
    monkeypatch.setattr(decisions, "decide", decide)

    say(client, "我说我今天吃的")

    input_text = decide.calls[-1][0]
    assert "Recent chat, oldest first (context only):\nUser: 多少卡?\nGuide: " in input_text
    assert input_text.endswith("Chat message:\n我说我今天吃的")


# ---------------------------------------------------------------- what the Guide knows


def test_todays_checkin_and_the_calorie_question_reach_the_guide(client, monkeypatch):
    provider = use(monkeypatch, ScriptedProvider())  # the Mock's scripts, recorded
    say(client, ATE)  # routed to checkin by the Mock

    reply = say(client, "roughly how many calories was my lunch?")[1]

    prompt = provider.system_prompts("guide")[-1]
    context = json.loads(prompt.split("<context>\n")[1].split("\n</context>")[0])
    assert context["todays_checkin"]["meals"] == "lunch: a sausage roll and ice cream"
    assert context["todays_checkin"]["sleep_hours"] == 7
    assert provider.calls_for("guide")[-1][-1]["content"] == "roughly how many calories was my lunch?"
    assert "kcal" in reply["content"] and "rough" in reply["content"]
    assert reply["agent"] == "front_desk"


def test_audits_facts_quests_and_nodes_reach_the_guide(client, client_engine, monkeypatch):
    with Session(client_engine) as session:
        skill = make_skill(session, make_course(session), "q", "Quadratic Equations")
        make_audit(session, skill, AuditStatus.failed, gaps_json=json.dumps(["no why"]))
        session.add(LifeFact(category=FactCategory.schedule, text="Works night shifts"))
        session.commit()
    provider = use(monkeypatch, ScriptedProvider(front_desk=desk()))

    say(client, "how am I doing with things")

    prompt = provider.system_prompts("guide")[-1]
    context = json.loads(prompt.split("<context>\n")[1].split("\n</context>")[0])
    assert context["recent_audits"] == [
        {"node": "Quadratic Equations", "result": "failed", "date": context["recent_audits"][0]["date"], "gaps": ["no why"]}
    ]
    assert context["lasting_facts"][0]["text"] == "Works night shifts"
    assert context["nodes"] == ["Quadratic Equations"]
    assert context["todays_checkin"] is None
    assert context["condition"]["flag"] == "unknown"


def test_older_lines_that_share_words_come_back(client, client_engine, monkeypatch):
    with Session(client_engine) as session:
        session.add(ChatMessage(role="user", content="my left knee hurts after running"))
        for i in range(20):
            session.add(ChatMessage(role="assistant", content=f"filler {i}", agent="front_desk"))
        session.commit()
    provider = use(monkeypatch, ScriptedProvider(front_desk=desk()))

    say(client, "should I still go running with this knee?")

    prompt = provider.system_prompts("guide")[-1]
    older = prompt.split("<older>\n")[1].split("\n</older>")[0]
    recent = prompt.split("<recent>\n")[1].split("\n</recent>")[0]
    assert older == "User: my left knee hurts after running"
    assert "knee" not in recent and len(recent.splitlines()) == 12


def test_the_guide_gets_the_front_desks_draft(client, monkeypatch):
    provider = use(monkeypatch, ScriptedProvider(front_desk=desk(reply="What topic should I build?")))

    say(client, "I want to learn")

    assert "<draft>\nWhat topic should I build?\n</draft>" in provider.system_prompts("guide")[-1]


def test_the_guide_writes_in_the_language_of_the_message(client, monkeypatch):
    from app.i18n import current_language

    seen = []

    def guide(messages):
        seen.append(current_language())
        return json.dumps({"reply": "好的。"})

    use(monkeypatch, ScriptedProvider(front_desk=desk(), guide=guide))

    assert say(client, "我今天有点累，聊聊吧", "en")[1]["content"] == "好的。"
    assert seen == ["zh"]


# ---------------------------------------------------------------- failures


def test_a_failing_guide_keeps_the_front_desks_reply(client, monkeypatch):
    use(monkeypatch, ScriptedProvider(front_desk=desk(reply="Sure, what would you like?"), guide=broken))

    messages = say(client, "hello there")

    assert [m["role"] for m in messages] == ["user", "assistant"]
    assert messages[1]["content"] == "Sure, what would you like?"


def test_unusable_guide_output_keeps_the_front_desks_reply(client, monkeypatch):
    use(monkeypatch, ScriptedProvider(front_desk=desk(reply="Sure."), guide="not json"))

    assert say(client, "hello there")[1]["content"] == "Sure."


def test_the_guide_does_not_run_for_actions(client, monkeypatch):
    provider = use(monkeypatch, ScriptedProvider(front_desk=desk("open_map", "Opening.")))

    say(client, "show me the map")

    assert provider.calls_for("guide") == []


# ---------------------------------------------------------------- check-in feedback


def test_a_logged_checkin_gets_one_guide_line(client, monkeypatch):
    provider = use(monkeypatch, ScriptedProvider())

    messages = say(client, "I slept 4 hours and I'm tired.")

    assert [m["agent"] for m in messages] == [None, "front_desk", "checkin_converter", "front_desk"]
    line = messages[3]["content"]
    assert "4 h" in line and "short" in line
    assert messages[3]["action"] is None
    context = json.loads(provider.system_prompts("guide")[0].split("<context>\n")[1].split("\n</context>")[0])
    assert context["checkin"]["sleep_hours"] == 4
    assert context["condition"]["flag"] == "low"
    assert "Mode: checkin_feedback" in provider.system_prompts("guide")[0]


def test_a_failing_feedback_line_is_left_out(client, monkeypatch):
    use(monkeypatch, ScriptedProvider(guide=broken))

    messages = say(client, "I slept 4 hours and I'm tired.")

    assert [m["agent"] for m in messages] == [None, "front_desk", "checkin_converter"]


def test_a_checkin_that_found_nothing_gets_no_feedback(client, monkeypatch):
    provider = use(monkeypatch, ScriptedProvider(front_desk=desk("checkin", "Logging.")))

    messages = say(client, "hmm")

    assert len(messages) == 3
    assert provider.calls_for("guide") == []


# ---------------------------------------------------------------- remembering


def test_a_plain_message_goes_to_the_fact_keeper_and_the_day_gate(client_engine, monkeypatch):
    monkeypatch.setattr(settings, "openai_api_key", "sk-test")
    monkeypatch.setattr(decisions, "decide", deciding("none", confidence=0.2))
    remembered, logged = [], []
    provider = ScriptedProvider(front_desk=desk())

    with Session(client_engine) as session:
        chat_service.handle_message(
            session, "I had ramen, how many calories is that?", lambda agent: provider, lambda: None,
            remember=remembered.append, log_said=logged.append,
        )

    assert remembered == logged == ["I had ramen, how many calories is that?"]


def test_without_the_day_gate_nothing_is_logged_from_plain_chat(client_engine):
    logged = []
    provider = ScriptedProvider(front_desk=desk())

    with Session(client_engine) as session:
        chat_service.handle_message(session, "hello there", lambda agent: provider, lambda: None, log_said=logged.append)

    assert logged == []
