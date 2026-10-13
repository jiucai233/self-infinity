"""The log of LLM calls (app/llm/usage.py) and what they cost (contract #47)."""

import threading

import httpx
import pytest
from sqlalchemy import inspect, text
from sqlmodel import Session, select

import app.db as app_db
from app.config import settings
from app.llm import usage
from app.llm.gemini import GeminiProvider
from app.models import LLMCall
from app.services import llm_usage
from tests.helpers import FIRST, LONG, agent_in, fake_llm_http, generate, ids_by_slug, openai_reply, start
from tests.test_accounts import ALICE, BOB, accounts_fixture, auth  # noqa: F401


def calls(engine) -> list[LLMCall]:
    with Session(engine) as session:
        return list(session.exec(select(LLMCall).order_by(LLMCall.id)).all())


# ---------------------------------------------------------------- the log


def test_a_request_logs_its_call_with_the_tokens(api, client_engine, monkeypatch):
    monkeypatch.setattr(settings, "openai_api_key", "k")
    sent = fake_llm_http(
        monkeypatch, lambda request: openai_reply({"needs_clarification": False}, prompt=1200, cached=1000, completion=30)
    )

    assert api.post("/api/skills/clarify", json={"topic": "Linear algebra"}).status_code == 200

    assert str(sent[0].url) == "https://api.openai.com/v1/chat/completions"
    (row,) = calls(client_engine)
    assert (row.agent, row.provider, row.model, row.ok) == ("clarifier", "openai", "gpt-6-luna", True)
    # prompt_tokens already counts the cached ones.
    assert (row.input_tokens, row.cached_tokens, row.output_tokens) == (1200, 1000, 30)
    assert row.audit_id is None and row.elapsed_ms >= 0


def test_a_reply_without_usage_is_logged_with_zeros(api, client_engine, monkeypatch):
    monkeypatch.setattr(settings, "openai_api_key", "k")
    reply = httpx.Response(200, json={"choices": [{"message": {"content": '{"needs_clarification": false}'}}]})
    fake_llm_http(monkeypatch, lambda request: reply)

    api.post("/api/skills/clarify", json={"topic": "Linear algebra"})

    (row,) = calls(client_engine)
    assert (row.ok, row.input_tokens, row.cached_tokens, row.output_tokens) == (True, 0, 0, 0)


@pytest.mark.parametrize(
    "reply",
    [httpx.Response(500, text="boom"), httpx.Response(200, json={"choices": []}), httpx.ConnectError("down")],
)
def test_a_failed_call_is_logged_as_failed(api, client_engine, monkeypatch, reply):
    monkeypatch.setattr(settings, "openai_api_key", "k")
    monkeypatch.setattr(settings, "llm_model", "gpt-6-sol")

    def handler(request):
        if isinstance(reply, Exception):
            raise reply
        return reply

    fake_llm_http(monkeypatch, handler)

    # The Clarifier swallows the failure (no clarification); the log keeps it.
    assert api.post("/api/skills/clarify", json={"topic": "Linear algebra"}).status_code == 200

    (row,) = calls(client_engine)
    assert (row.agent, row.provider, row.model) == ("clarifier", "openai", "gpt-6-sol")
    assert (row.ok, row.input_tokens, row.cached_tokens, row.output_tokens) == (False, 0, 0, 0)


def test_the_mock_provider_logs_nothing(api, client_engine):
    generate(api)
    assert api.post("/api/skills/clarify", json={"topic": "x"}).status_code == 200
    assert calls(client_engine) == []


def test_an_audit_answer_logs_the_auditor_and_the_challenger_with_its_id(api, client_engine, monkeypatch):
    skill = ids_by_slug(generate(api))["discriminant"]
    audit_id = start(api, skill)  # everything so far on the mock: nothing logged
    monkeypatch.setattr(settings, "openai_api_key", "k")

    def handler(request):
        if agent_in(request) == "challenger":
            return openai_reply({"action": "overturn", "question": "And when it is zero?", "reason": "r"}, 700, 0, 40)
        verdict = {"action": "verdict", "pass": True, "score": 90, "gaps": [], "comment": "Clear."}
        return openai_reply(verdict, prompt=900, cached=500, completion=60)

    fake_llm_http(monkeypatch, handler)
    # The votes are judged in parallel threads; the test engine is one in-memory connection shared
    # by all of them, which cannot take two writes at once (a file database can).
    lock, write = threading.Lock(), usage.record

    def one_at_a_time(**kwargs):
        with lock:
            write(**kwargs)

    monkeypatch.setattr(usage, "record", one_at_a_time)

    result = api.post(f"/api/audits/{audit_id}/turns", json={"content": LONG})

    assert result.json()["question"] == "And when it is zero?"
    rows = calls(client_engine)
    # The first judgement comes first; the other two and the Challenger run at once, in any order.
    assert (rows[0].agent, rows[0].audit_id, rows[0].ok) == ("auditor", audit_id, True)
    assert sorted((r.agent, r.audit_id, r.ok) for r in rows) == [("auditor", audit_id, True)] * 3 + [("challenger", audit_id, True)]
    assert (rows[0].input_tokens, rows[0].cached_tokens, rows[0].output_tokens) == (900, 500, 60)

    # Another request of the same account starts without an audit.
    api.post("/api/skills/clarify", json={"topic": "Linear algebra"})
    assert calls(client_engine)[-1].audit_id is None


def test_an_auditor_that_fails_is_logged_with_the_audit(api, client_engine, monkeypatch):
    skill = ids_by_slug(generate(api))["discriminant"]
    audit_id = start(api, skill)
    monkeypatch.setattr(settings, "openai_api_key", "k")
    fake_llm_http(monkeypatch, lambda request: httpx.Response(503, text="busy"))

    assert api.post(f"/api/audits/{audit_id}/turns", json={"content": FIRST}).status_code == 502

    rows = calls(client_engine)
    assert rows and all((r.agent, r.audit_id, r.ok) == ("auditor", audit_id, False) for r in rows)


def test_each_account_has_its_own_log(accounts, client_engine, monkeypatch):
    monkeypatch.setattr(settings, "openai_api_key", "k")
    monkeypatch.setattr(settings, "dev_emails", "alice@example.com,bob@example.com")
    fake_llm_http(monkeypatch, lambda request: openai_reply({"needs_clarification": False}, 10, 0, 5))
    alice, bob = auth(ALICE, email="alice@example.com"), auth(BOB, email="bob@example.com")

    accounts.post("/api/skills/clarify", json={"topic": "Linear algebra"}, headers=alice)

    assert accounts.get("/api/dev/llm", headers=alice).json()["totals"]["calls"] == 1
    assert accounts.get("/api/dev/llm", headers=bob).json()["totals"]["calls"] == 0


def test_gemini_logs_its_usage_metadata():
    class Usage:
        prompt_token_count = 400
        cached_content_token_count = 300
        candidates_token_count = 20

    class Response:
        text = '{"ok": true}'
        usage_metadata = Usage()

    class Models:
        def generate_content(self, **kwargs):
            return Response()

    class Client:
        models = Models()

    provider = GeminiProvider.__new__(GeminiProvider)
    provider._client = Client()
    seen = []
    token = usage.begin()
    usage.current().bind = object()  # never used: record is replaced below
    try:
        with pytest.MonkeyPatch.context() as mp:
            mp.setattr(usage, "record", lambda **row: seen.append(row))
            provider.complete([{"role": "system", "content": "[agent: planner]\nx"}, {"role": "user", "content": "hi"}])
    finally:
        usage.end(token)

    (row,) = seen
    assert (row["provider"], row["model"], row["agent"], row["ok"]) == ("gemini", "gemini-2.5-flash", "planner", True)
    assert (row["input_tokens"], row["cached_tokens"], row["output_tokens"]) == (400, 300, 20)


def test_a_log_that_cannot_be_written_never_breaks_the_call(caplog):
    token = usage.begin()
    usage.current().bind = object()  # not an engine: the write fails
    try:
        usage.record(provider="openai", model="gpt-6-luna", agent="auditor", input_tokens=1)
    finally:
        usage.end(token)
    assert "could not log an LLM call" in caplog.text


def test_a_background_task_of_the_request_still_logs(api, client_engine, monkeypatch):
    # A check-in's Fact Keeper runs after the response, in the request's context.
    monkeypatch.setattr(settings, "openai_api_key", "k")
    monkeypatch.setattr("app.llm.decisions.available", lambda: False)

    def handler(request):
        if agent_in(request) == "fact_keeper":
            return openai_reply({"changes": []}, 300, 0, 10)
        return openai_reply({"sleep_hours": 7}, 200, 0, 10)

    fake_llm_http(monkeypatch, handler)

    api.post("/api/checkins", json={"transcript": "I slept seven hours and my knee is injured for six weeks"})

    assert "fact_keeper" in {r.agent for r in calls(client_engine)}


# ---------------------------------------------------------------- an account that already exists


def test_an_existing_account_schema_gets_the_new_table_and_column(client_engine, monkeypatch):
    monkeypatch.setattr(app_db, "_ready", set())
    schema = "u_old"
    app_db.ensure_schema(client_engine, schema)
    # The schema as it was before this release: no call log, no provider on the profile.
    with client_engine.begin() as conn:
        conn.execute(text(f'DROP TABLE "{schema}".llmcall'))
        conn.execute(text(f'ALTER TABLE "{schema}".profile DROP COLUMN llm_provider'))
        conn.execute(text(f'INSERT INTO "{schema}".profile (id, identity, vision, anti_vision, rules_json) VALUES (1, \'me\', \'\', \'\', \'[]\')'))
    assert "llmcall" not in inspect(client_engine).get_table_names(schema=schema)

    # A new process: the schema is set up again on the account's first request.
    monkeypatch.setattr(app_db, "_ready", set())
    scoped = app_db.ensure_schema(client_engine, schema)

    inspector = inspect(client_engine)
    assert "llmcall" in inspector.get_table_names(schema=schema)
    assert "llm_provider" in {c["name"] for c in inspector.get_columns("profile", schema=schema)}
    assert {i["name"] for i in inspector.get_indexes("llmcall", schema=schema)} == {"ix_llmcall_audit_id"}
    with Session(scoped) as session:
        session.add(LLMCall(provider="openai", model="gpt-6-luna", audit_id=3))
        session.commit()
        from app.models import Profile

        row = session.get(Profile, 1)
        assert (row.identity, row.llm_provider) == ("me", None)


# ---------------------------------------------------------------- what it costs


def test_prices_are_per_million_tokens_with_cached_input_cheaper():
    call = LLMCall(provider="openai", model="gpt-6-luna", input_tokens=10_000, cached_tokens=4_000, output_tokens=1_000)
    assert llm_usage.call_cost(call) == pytest.approx((6_000 * 0.10 + 4_000 * 0.01 + 1_000 * 0.50) / 1e6)
    assert llm_usage.call_cost(LLMCall(provider="openai", model="some-other-model", input_tokens=5)) is None
    assert llm_usage.PRICES["claude-haiku-5-5"] == (0.10, 0.01, 0.50)
    assert llm_usage.PRICES["claude-sonnet-5-5"] == (2.0, 0.10, 10.0)
    assert llm_usage.PRICES["claude-opus-5-5"] == (4.0, 0.20, 20.0)
    assert llm_usage.PRICES["gpt-6-sol"] == (1.25, 0.125, 10.0)


LUNA = {"provider": "openai", "model": "gpt-6-luna"}
SONNET = {"provider": "claude", "model": "claude-sonnet-5-5"}
ROWS = [
    LLMCall(agent="auditor", **LUNA, input_tokens=10_000, cached_tokens=4_000, output_tokens=1_000, elapsed_ms=2_000, audit_id=1),
    LLMCall(agent="challenger", **LUNA, input_tokens=5_000, output_tokens=200, elapsed_ms=1_000, audit_id=1),
    LLMCall(agent="auditor", **LUNA, elapsed_ms=500, ok=False, audit_id=1),
    LLMCall(agent="auditor", **SONNET, input_tokens=8_000, output_tokens=1_000, elapsed_ms=3_000, audit_id=2),
    LLMCall(agent="planner", provider="openai", model="my-own-model", input_tokens=1_000, output_tokens=100, elapsed_ms=4_000),
    LLMCall(agent="auditor", **SONNET, input_tokens=2_000, output_tokens=500, elapsed_ms=1_000, audit_id=3),
]
AUDITOR_LUNA = (6_000 * 0.10 + 4_000 * 0.01 + 1_000 * 0.50) / 1e6  # 0.00114
CHALLENGER_LUNA = (5_000 * 0.10 + 200 * 0.50) / 1e6  # 0.0006
SONNET_2 = (8_000 * 2.0 + 1_000 * 10.0) / 1e6  # 0.026
SONNET_3 = (2_000 * 2.0 + 500 * 10.0) / 1e6  # 0.009


def test_the_developer_panel_prices_the_log(client, client_engine):
    with Session(client_engine) as session:
        session.add_all([LLMCall(**row.model_dump(exclude={"id"})) for row in ROWS])
        session.commit()

    data = client.get("/api/dev/llm").json()

    total = AUDITOR_LUNA + CHALLENGER_LUNA + SONNET_2 + SONNET_3
    assert data["totals"] == {
        "calls": 6,
        "failed": 1,
        "cost": pytest.approx(total),
        # Per call that succeeded on a model with a price: four of them.
        "avg_cost": pytest.approx(total / 4, abs=1e-6),
        "unpriced_calls": 1,
    }

    # By cost, highest first; the model without a price last.
    assert data["providers"] == [
        {
            **SONNET, "calls": 2, "failed": 0, "input_tokens": 10_000, "cached_tokens": 0, "output_tokens": 1_500,
            "avg_ms": 2_000, "cost": pytest.approx(SONNET_2 + SONNET_3), "avg_cost": pytest.approx((SONNET_2 + SONNET_3) / 2),
        },
        {
            **LUNA, "calls": 3, "failed": 1, "input_tokens": 15_000, "cached_tokens": 4_000, "output_tokens": 1_200,
            "avg_ms": 1_500, "cost": pytest.approx(AUDITOR_LUNA + CHALLENGER_LUNA),
            "avg_cost": pytest.approx((AUDITOR_LUNA + CHALLENGER_LUNA) / 2),
        },
        {
            "provider": "openai", "model": "my-own-model", "calls": 1, "failed": 0, "input_tokens": 1_000,
            "cached_tokens": 0, "output_tokens": 100, "avg_ms": 4_000, "cost": None, "avg_cost": None,
        },
    ]

    assert [(a["agent"], a["model"], a["calls"]) for a in data["agents"]] == [
        ("auditor", "claude-sonnet-5-5", 2),
        ("auditor", "gpt-6-luna", 2),
        ("challenger", "gpt-6-luna", 1),
        ("planner", "my-own-model", 1),
    ]
    auditor_luna = data["agents"][1]
    # The failed call counts as a call and nowhere else.
    assert auditor_luna == {
        "agent": "auditor", **LUNA, "calls": 2, "avg_input_tokens": 10_000, "avg_output_tokens": 1_000, "avg_ms": 2_000,
        "cost": pytest.approx(AUDITOR_LUNA), "avg_cost": pytest.approx(AUDITOR_LUNA),
    }
    assert data["agents"][0]["avg_input_tokens"] == 5_000 and data["agents"][0]["avg_output_tokens"] == 750
    assert (data["agents"][3]["cost"], data["agents"][3]["avg_cost"]) == (None, None)

    # Audit 1 ran on gpt-6-luna (three calls), audits 2 and 3 on Sonnet (one call each).
    assert data["audits"] == [
        {**SONNET, "audits": 2, "avg_calls": 1.0, "avg_cost": pytest.approx((SONNET_2 + SONNET_3) / 2)},
        {**LUNA, "audits": 1, "avg_calls": 3.0, "avg_cost": pytest.approx(AUDITOR_LUNA + CHALLENGER_LUNA)},
    ]


def test_an_audit_with_an_unpriced_call_is_counted_but_not_averaged(client, client_engine):
    with Session(client_engine) as session:
        session.add(LLMCall(agent="auditor", **LUNA, input_tokens=1_000, audit_id=1))
        session.add(LLMCall(agent="auditor", provider="openai", model="my-own-model", input_tokens=1_000, audit_id=2))
        session.add(LLMCall(agent="auditor", provider="openai", model="my-own-model", input_tokens=1_000, audit_id=1))
        session.add(LLMCall(agent="auditor", **LUNA, input_tokens=3_000, audit_id=1))
        session.add(LLMCall(agent="auditor", **LUNA, input_tokens=2_000, audit_id=4))
        session.commit()

    audits = client.get("/api/dev/llm").json()["audits"]

    # Audit 1 mixed two models (most calls on gpt-6-luna): its cost is not known, audit 4's is.
    assert audits == [
        {**LUNA, "audits": 2, "avg_calls": 2.0, "avg_cost": pytest.approx(2_000 * 0.10 / 1e6)},
        {"provider": "openai", "model": "my-own-model", "audits": 1, "avg_calls": 1.0, "avg_cost": None},
    ]


def test_an_empty_log(client):
    assert client.get("/api/dev/llm").json() == {
        "totals": {"calls": 0, "failed": 0, "cost": 0.0, "avg_cost": None, "unpriced_calls": 0},
        "providers": [],
        "agents": [],
        "audits": [],
        "all_on": [],
    }


def test_every_text_call_is_priced_on_each_model(client, client_engine):
    with Session(client_engine) as session:
        # Two calls on OpenAI (one with a cache hit), one on Claude, a failed one, and speech.
        session.add(LLMCall(agent="auditor", provider="openai", model="gpt-6-luna", input_tokens=10_000, cached_tokens=8_000, output_tokens=1_000))
        session.add(LLMCall(agent="planner", provider="openai", model="gpt-6-luna", input_tokens=4_000, output_tokens=2_000))
        session.add(LLMCall(agent="auditor", provider="claude", model="claude-haiku-5-5", input_tokens=6_000, output_tokens=500))
        session.add(LLMCall(agent="auditor", provider="openai", model="gpt-6-luna", ok=False))
        session.add(LLMCall(agent="speech", provider="openai", model="gpt-4o-mini-tts", input_tokens=50, output_tokens=300))
        session.commit()

    data = client.get("/api/dev/llm").json()

    rows = {r["model"]: r for r in data["all_on"]}
    assert set(rows) == {"gpt-6-luna", "gpt-6-sol", "claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5"}
    assert (rows["gpt-6-luna"]["provider"], rows["claude-opus-5-5"]["provider"]) == ("openai", "claude")
    out = 3_500
    # On an OpenAI model the OpenAI call's cached tokens stay cached; Claude's call had none.
    luna = (12_000 * 0.10 + 8_000 * 0.01 + out * 0.50) / 1e6
    assert rows["gpt-6-luna"]["cost"] == pytest.approx(luna, abs=1e-6)
    assert rows["gpt-6-sol"]["cost"] == pytest.approx((12_000 * 1.25 + 8_000 * 0.125 + out * 10.0) / 1e6, abs=1e-6)
    # On Claude nothing would have come from OpenAI's cache: every input token at full price.
    assert rows["claude-haiku-5-5"]["cost"] == pytest.approx((20_000 * 0.10 + out * 0.50) / 1e6, abs=1e-6)
    assert [r["cost"] for r in data["all_on"]] == sorted(r["cost"] for r in data["all_on"])  # cheapest first
    # Speech is a call with a price of its own, and is not priced on a text model.
    speech = next(r for r in data["agents"] if r["agent"] == "speech")
    assert speech["cost"] == pytest.approx((50 * 0.60 + 300 * 12.0) / 1e6, abs=1e-6)


def test_only_developers_see_the_costs(accounts, monkeypatch):
    monkeypatch.setattr(settings, "dev_emails", "alice@example.com")
    assert accounts.get("/api/dev/llm", headers=auth(ALICE, email="alice@example.com")).status_code == 200
    bob = accounts.get("/api/dev/llm", headers=auth(BOB, email="bob@example.com"))
    assert (bob.status_code, bob.json()) == (403, {"detail": "developers only"})
    assert accounts.get("/api/dev/llm").status_code == 401


# ---------------------------------------------------------------- speech


def test_streamed_speech_is_logged_by_the_length_of_its_audio(api, client_engine, monkeypatch):
    from app.services import voice

    monkeypatch.setattr(settings, "openai_api_key", "sk-test")
    pcm = bytes(voice.PCM_RATE * 2 * 3)  # three seconds of 16-bit mono
    monkeypatch.setattr(voice, "_client", httpx.Client(transport=httpx.MockTransport(lambda r: httpx.Response(200, content=pcm))))

    assert api.post("/api/voice/speech/stream", json={"text": "Right. What happens without the softmax?"}).content == pcm

    (row,) = calls(client_engine)
    assert (row.agent, row.provider, row.model, row.ok) == ("speech", "openai", "gpt-4o-mini-tts", True)
    assert row.output_tokens == 3 * voice.SPEECH_TOKENS_PER_SECOND
    assert row.input_tokens == 12  # 40 bytes of text
    assert llm_usage.call_cost(row) == pytest.approx((12 * 0.60 + 60 * 12.0) / 1e6)


def test_speech_as_a_file_is_logged_too(api, client_engine, monkeypatch):
    from app.services import voice

    monkeypatch.setattr(settings, "openai_api_key", "sk-test")
    mp3 = bytes([0xFF, 0xF3, 0x84, 0xC4]) + bytes(16_000 - 4)  # two seconds at 64 kbit/s
    monkeypatch.setattr(voice, "_client", httpx.Client(transport=httpx.MockTransport(lambda r: httpx.Response(200, content=mp3))))

    assert api.post("/api/voice/speech", json={"text": "Go on."}).status_code == 200

    (row,) = calls(client_engine)
    assert (row.agent, row.output_tokens) == ("speech", 40)
