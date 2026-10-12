"""Each account chooses the provider its agents run on (contract #46): GET/PUT /api/llm."""

import json

import pytest
from sqlmodel import Session

from app.config import settings
from app.llm import get_provider, usage
from app.models import Profile
from tests.helpers import agent_in, claude_reply, fake_llm_http, openai_reply
from tests.test_accounts import ALICE, BOB, accounts_fixture, auth  # noqa: F401
from tests.test_llm_usage import calls

OPENAI = {"id": "openai", "model": "gpt-6-luna"}
CLAUDE = {"id": "claude", "model": "claude-haiku-5-5"}


@pytest.fixture(name="both_keys")
def both_keys_fixture(monkeypatch):
    monkeypatch.setattr(settings, "openai_api_key", "k-openai")
    monkeypatch.setattr(settings, "anthropic_api_key", "k-claude")


def reply(request):
    """A Clarifier answer from whichever provider was asked."""
    answer = {"needs_clarification": False}
    if request.url.host == "api.anthropic.com":
        return claude_reply(answer, fresh=50, output=10)
    return openai_reply(answer, prompt=50, completion=10)


def clarify(client, **kwargs) -> None:
    assert client.post("/api/skills/clarify", json={"topic": "Linear algebra"}, **kwargs).status_code == 200


def test_without_keys_the_account_runs_on_the_mock(api):
    assert api.get("/api/llm").json() == {
        "provider": "mock",
        "model": "",
        "choices": [{**OPENAI, "available": False}, {**CLAUDE, "available": False}],
    }


def test_the_servers_provider_is_the_default(api, monkeypatch):
    monkeypatch.setattr(settings, "openai_api_key", "k")
    assert api.get("/api/llm").json() == {
        "provider": "openai",
        "model": "gpt-6-luna",
        "choices": [{**OPENAI, "available": True}, {**CLAUDE, "available": False}],
    }


def test_adding_claudes_key_changes_nothing_by_itself(api, both_keys, monkeypatch):
    sent = fake_llm_http(monkeypatch, reply)
    assert api.get("/api/llm").json() == {
        "provider": "openai",
        "model": "gpt-6-luna",
        "choices": [{**OPENAI, "available": True}, {**CLAUDE, "available": True}],
    }
    clarify(api)
    assert [r.url.host for r in sent] == ["api.openai.com"]


def test_choosing_a_provider_saves_it(api, client_engine, both_keys, monkeypatch):
    sent = fake_llm_http(monkeypatch, reply)
    api.put("/api/profile", json={"identity": "I am a learner"})
    saved_at = api.get("/api/profile").json()["updated_at"]

    chosen = api.put("/api/llm", json={"provider": "claude"})

    assert chosen.status_code == 200
    assert chosen.json() == {
        "provider": "claude",
        "model": "claude-haiku-5-5",
        "choices": [{**OPENAI, "available": True}, {**CLAUDE, "available": True}],
    }
    assert api.get("/api/llm").json() == chosen.json()
    with Session(client_engine) as session:
        assert session.get(Profile, 1).llm_provider == "claude"
    # The rules of the game are untouched, and neither endpoint called a model.
    profile = api.get("/api/profile").json()
    assert (profile["identity"], profile["updated_at"]) == ("I am a learner", saved_at)
    assert sent == []

    assert api.put("/api/llm", json={"provider": "openai"}).json()["provider"] == "openai"


def test_a_first_choice_creates_the_profile_row(api, client_engine, both_keys):
    assert api.put("/api/llm", json={"provider": "claude"}).status_code == 200
    profile = api.get("/api/profile").json()
    assert (profile["identity"], profile["rules"], profile["onboarded"]) == ("", [], False)


def test_a_provider_without_a_key_cannot_be_chosen(api, client_engine, monkeypatch):
    monkeypatch.setattr(settings, "openai_api_key", "k")
    refused = api.put("/api/llm", json={"provider": "claude"})
    assert (refused.status_code, refused.json()) == (400, {"detail": "claude is not set up on this server"})
    with Session(client_engine) as session:
        assert session.get(Profile, 1) is None


@pytest.mark.parametrize("body", [{"provider": "gemini"}, {"provider": "mock"}, {"provider": ""}, {"provider": None}, {}])
def test_anything_else_is_a_422(api, both_keys, body):
    assert api.put("/api/llm", json=body).status_code == 422


def test_the_chosen_provider_runs_the_agents_on_its_own_model(api, client_engine, both_keys, monkeypatch):
    # LLM_MODEL and the overrides name OpenAI models: they must not reach Claude.
    monkeypatch.setattr(settings, "llm_model", "gpt-6-sol")
    monkeypatch.setattr(settings, "llm_model_overrides", '{"clarifier": "gpt-6-sol"}')
    sent = fake_llm_http(monkeypatch, reply)
    api.put("/api/llm", json={"provider": "claude"})

    clarify(api)

    (request,) = sent
    assert str(request.url) == "https://api.anthropic.com/v1/messages"
    assert request.headers["x-api-key"] == "k-claude"
    assert json.loads(request.content)["model"] == "claude-haiku-5-5"
    assert agent_in(request) == "clarifier"
    (row,) = calls(client_engine)
    assert (row.agent, row.provider, row.model, row.input_tokens, row.output_tokens) == (
        "clarifier", "claude", "claude-haiku-5-5", 50, 10,
    )


def test_choosing_the_servers_provider_keeps_its_models(api, both_keys, monkeypatch):
    monkeypatch.setattr(settings, "llm_model", "gpt-6-sol")
    monkeypatch.setattr(settings, "llm_model_overrides", '{"clarifier": "gpt-6-luna"}')
    sent = fake_llm_http(monkeypatch, reply)

    chosen = api.put("/api/llm", json={"provider": "openai"}).json()
    clarify(api)

    assert (chosen["provider"], chosen["model"]) == ("openai", "gpt-6-sol")
    assert chosen["choices"][0] == {"id": "openai", "model": "gpt-6-sol", "available": True}
    assert json.loads(sent[0].content)["model"] == "gpt-6-luna"  # the Clarifier's override


def test_openai_chosen_on_a_claude_server_runs_on_openais_default(api, both_keys, monkeypatch):
    monkeypatch.setattr(settings, "llm_provider", "claude")
    monkeypatch.setattr(settings, "llm_model", "claude-sonnet-5-5")
    monkeypatch.setattr(settings, "llm_model_overrides", '{"clarifier": "claude-opus-5-5"}')
    sent = fake_llm_http(monkeypatch, reply)
    assert api.get("/api/llm").json() == {
        "provider": "claude",
        "model": "claude-sonnet-5-5",
        "choices": [{**OPENAI, "available": True}, {"id": "claude", "model": "claude-sonnet-5-5", "available": True}],
    }

    clarify(api)
    assert json.loads(sent[-1].content)["model"] == "claude-opus-5-5"

    assert api.put("/api/llm", json={"provider": "openai"}).json()["model"] == "gpt-6-luna"
    clarify(api)
    assert sent[-1].url.host == "api.openai.com"
    assert json.loads(sent[-1].content)["model"] == "gpt-6-luna"


def test_a_choice_whose_key_is_gone_falls_back_to_the_server(api, both_keys, monkeypatch):
    sent = fake_llm_http(monkeypatch, reply)
    api.put("/api/llm", json={"provider": "claude"})
    monkeypatch.setattr(settings, "anthropic_api_key", "")

    assert api.get("/api/llm").json()["provider"] == "openai"
    clarify(api)
    assert sent[-1].url.host == "api.openai.com"


def test_outside_a_request_it_is_the_servers_provider(api, both_keys):
    api.put("/api/llm", json={"provider": "claude"})

    assert usage.current() is None
    assert get_provider("clarifier").name == "openai"
    # Health has no account either.
    assert api.get("/api/health").json()["llm_provider"] == "openai"


def test_the_choice_is_read_once_a_request(client_engine, both_keys):
    with Session(client_engine) as session:
        session.add(Profile(id=1, llm_provider="claude"))
        session.commit()
    token = usage.begin()
    try:
        usage.current().bind = client_engine
        assert get_provider().name == "claude"
        with Session(client_engine) as session:
            session.get(Profile, 1).llm_provider = "openai"
            session.commit()
        assert get_provider().name == "claude"
    finally:
        usage.end(token)


def test_each_account_has_its_own_choice(accounts, both_keys, monkeypatch):
    sent = fake_llm_http(monkeypatch, reply)
    alice, bob = auth(ALICE), auth(BOB)

    accounts.put("/api/llm", json={"provider": "claude"}, headers=alice)

    assert accounts.get("/api/llm", headers=alice).json()["provider"] == "claude"
    assert accounts.get("/api/llm", headers=bob).json()["provider"] == "openai"
    clarify(accounts, headers=alice)
    clarify(accounts, headers=bob)
    assert [r.url.host for r in sent] == ["api.anthropic.com", "api.openai.com"]
    assert accounts.get("/api/llm").status_code == 401


def test_clarify_needs_an_account_like_every_endpoint(accounts):
    assert accounts.post("/api/skills/clarify", json={"topic": "Linear algebra"}).status_code == 401
