"""The front desk's fast path (contract section 5): the Decisions API picks the intent from
fixed choices; the LLM is asked only for a new course, small talk, or when unsure."""

import json

import httpx
import pytest

from app.agents.front_desk import NO_NODE, FrontDesk
from app.config import settings
from app.llm import decisions
from tests.helpers import ScriptedProvider, generate

TITLES = ["Quadratic Equations", "Discriminant"]


def llm_says(intent="none", args=None, reply="Sure."):
    return ScriptedProvider(front_desk=json.dumps({"intent": intent, "args": args or {}, "reply": reply}))


def deciding(intent, confidence=0.98, node=NO_NODE, node_confidence=0.98):
    calls = []

    def decide(input_text, questions):
        calls.append((input_text, questions))
        return {"intent": (intent, confidence), "node": (node, node_confidence)}

    decide.calls = calls
    return decide


# ---------------------------------------------------------------- the agent


@pytest.mark.parametrize(
    "intent, reply",
    [
        ("checkin", "Logging your day."),
        ("plan", "Let me pick today's quests."),
        ("briefing", "Here is where you stand."),
        ("open_map", "Here is your life tree."),
    ],
)
def test_a_confident_fixed_intent_never_asks_the_llm(intent, reply):
    provider = llm_says()

    result = FrontDesk(provider, decide=deciding(intent)).route("anything", TITLES)

    assert (result.intent, result.args, result.reply) == (intent, {}, reply)
    assert provider.calls_for("front_desk") == []


def test_a_named_node_opens_without_the_llm():
    provider = llm_says()

    result = FrontDesk(provider, decide=deciding("open_skill", node="Discriminant")).route("do the discriminant", TITLES)

    assert (result.intent, result.args, result.reply) == ("open_skill", {"skill": "Discriminant"}, "Opening “Discriminant”.")
    assert provider.calls_for("front_desk") == []


@pytest.mark.parametrize(
    "decide",
    [
        deciding("generate_course"),  # the topic has to be read out of the message
        deciding("none"),  # small talk needs a reply
        deciding("checkin", confidence=0.5),
        deciding("open_skill", node=NO_NODE),
        deciding("open_skill", node="Discriminant", node_confidence=0.4),
        deciding("open_skill", node="Not A Node"),
        deciding("start_audit"),
    ],
)
def test_the_llm_answers_when_the_fast_path_cannot(decide):
    provider = llm_says("generate_course", {"topic": "Rust"}, "On it.")

    result = FrontDesk(provider, decide=decide).route("I want to learn Rust", TITLES)

    assert (result.intent, result.args, result.reply) == ("generate_course", {"topic": "Rust"}, "On it.")
    assert len(provider.calls_for("front_desk")) == 1


def test_a_failing_decisions_call_falls_back_to_the_llm():
    def broken(input_text, questions):
        raise decisions.DecisionsFailed("down")

    provider = llm_says("plan", reply="Picking.")

    assert FrontDesk(provider, decide=broken).route("what now", TITLES).reply == "Picking."


def test_the_questions_carry_every_intent_and_every_node_once():
    decide = deciding("plan")

    FrontDesk(llm_says(), decide=decide).route("what now", TITLES + ["Discriminant"])

    input_text, questions = decide.calls[0]
    assert input_text == "Player's nodes:\n- Quadratic Equations\n- Discriminant\n\nChat message:\nwhat now"
    intent, node = questions
    assert [c["value"] for c in intent["choices"]] == [
        "generate_course", "open_skill", "checkin", "plan", "briefing", "open_map", "none",
    ]
    assert all(c["description"] for c in intent["choices"])
    assert node["choices"] == [{"value": "Quadratic Equations"}, {"value": "Discriminant"}, {"value": NO_NODE, "description": "It names none of them."}]


def test_without_nodes_there_is_no_node_question():
    decide = deciding("plan")

    FrontDesk(llm_says(), decide=decide).route("what now", [])

    assert [q["name"] for q in decide.calls[0][1]] == ["intent"]


# ---------------------------------------------------------------- the Decisions client


@pytest.fixture(name="openai")
def openai_fixture(monkeypatch):
    """A recording stand-in for api.openai.com; set `.reply` to an httpx.Response."""

    class Fake:
        pass

    Fake.requests = []
    Fake.reply = httpx.Response(200, json={"answers": [
        {"type": "choice", "name": "intent", "choice": "plan", "confidence": 0.94, "probabilities": []},
    ], "usage": {"input_tokens": 150}})

    def handler(request):
        Fake.requests.append(request)
        return Fake.reply

    monkeypatch.setattr(settings, "openai_api_key", "sk-test")
    monkeypatch.setattr(decisions, "_client", httpx.Client(transport=httpx.MockTransport(handler)))
    return Fake


def test_decide_posts_the_questions_and_reads_the_choices(openai):
    answers = decisions.decide("hi", [decisions.choice("intent", "What?", [("plan", "Asks."), ("none", "")])])

    assert answers == {"intent": ("plan", 0.94)}
    request = openai.requests[0]
    assert str(request.url) == "https://api.openai.com/v1/decisions"
    assert request.headers["Authorization"] == "Bearer sk-test"
    assert json.loads(request.content) == {"model": "gpt-6-luna", "input": "hi", "questions": [{
        "type": "choice", "name": "intent", "instructions": "What?",
        "choices": [{"value": "plan", "description": "Asks."}, {"value": "none"}],
    }]}


@pytest.mark.parametrize(
    "reply",
    [httpx.Response(500, text="boom"), httpx.Response(200, text="not json"), httpx.Response(200, json={"answers": "x"})],
)
def test_decide_raises_on_an_error_or_an_unreadable_answer(openai, reply):
    openai.reply = reply

    with pytest.raises(decisions.DecisionsFailed):
        decisions.decide("hi", [])


def test_decide_needs_the_key(monkeypatch):
    monkeypatch.setattr(settings, "openai_api_key", "")

    assert decisions.available() is False
    with pytest.raises(decisions.DecisionsFailed):
        decisions.decide("hi", [])


# ---------------------------------------------------------------- POST /api/chat


def test_chat_takes_the_fast_path_when_openai_is_configured(client, monkeypatch):
    generate(client, "Math")
    provider = ScriptedProvider()
    monkeypatch.setattr("app.routers.chat.get_provider", lambda agent=None: provider)
    monkeypatch.setattr(settings, "openai_api_key", "sk-test")
    monkeypatch.setattr(decisions, "decide", deciding("open_skill", node="Discriminant"))

    response = client.post("/api/chat", json={"message": "判别式那个"}, headers={"Accept-Language": "zh"})

    messages = response.json()["messages"]
    assert messages[1]["content"] == "打开「Discriminant」。"
    assert messages[1]["action"]["type"] == "navigate" and messages[1]["action"]["scene"] == "skill"
    assert provider.calls_for("front_desk") == []


def test_chat_without_the_openai_key_asks_the_llm(client, monkeypatch):
    provider = ScriptedProvider()
    monkeypatch.setattr("app.routers.chat.get_provider", lambda agent=None: provider)
    monkeypatch.setattr(decisions, "decide", lambda *a: pytest.fail("decisions called without a key"))

    client.post("/api/chat", json={"message": "Hello"})

    assert len(provider.calls_for("front_desk")) == 1
