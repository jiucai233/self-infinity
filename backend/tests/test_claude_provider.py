"""The Claude provider (app/llm/claude.py): the Messages API request, the reply, the usage log."""

import json

import httpx
import pytest
from sqlmodel import Session, SQLModel, create_engine, select
from sqlmodel.pool import StaticPool

from app.config import settings
from app.i18n import language_instruction, reset_language, set_language
from app.llm import get_provider, usage
from app.llm.claude import ClaudeAPIError, ClaudeEmptyResponseError, ClaudeProvider, json_object
from app.models import LLMCall
from tests.helpers import claude_reply

MESSAGES = [{"role": "system", "content": "[agent: auditor]\nJudge."}, {"role": "user", "content": "hi"}]


def make(reply: httpx.Response | Exception, model: str | None = None) -> tuple[ClaudeProvider, list[httpx.Request]]:
    sent: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        sent.append(request)
        if isinstance(reply, Exception):
            raise reply
        return reply

    provider = ClaudeProvider(model)
    provider._client = httpx.Client(transport=httpx.MockTransport(handler))
    return provider, sent


def body_of(request: httpx.Request) -> dict:
    return json.loads(request.content)


def test_the_request_is_a_messages_api_call(monkeypatch):
    monkeypatch.setattr(settings, "anthropic_api_key", "sk-ant-test")
    provider, sent = make(claude_reply({"ok": True}))

    assert provider.complete(MESSAGES) == '{"ok": true}'

    request = sent[0]
    assert (request.method, str(request.url)) == ("POST", "https://api.anthropic.com/v1/messages")
    assert request.headers["x-api-key"] == "sk-ant-test"
    assert request.headers["anthropic-version"] == "2023-06-01"
    assert request.headers["content-type"] == "application/json"
    assert "authorization" not in request.headers
    assert body_of(request) == {
        "model": "claude-haiku-5-5",
        "max_tokens": 16000,
        "system": "[agent: auditor]\nJudge.",
        "messages": [{"role": "user", "content": "hi"}],
    }


def test_no_sampling_parameters_are_sent():
    provider, sent = make(claude_reply({"ok": True}))
    provider.complete(MESSAGES)
    assert not {"temperature", "top_p", "top_k", "response_format"} & set(body_of(sent[0]))


def test_system_messages_are_joined_and_carry_the_language():
    provider, sent = make(claude_reply({"ok": True}))
    token = set_language("zh")
    try:
        instruction = language_instruction()
        provider.complete(
            [
                {"role": "system", "content": "[agent: auditor]\nFirst."},
                {"role": "user", "content": "hi"},
                {"role": "system", "content": "Second."},
            ]
        )
    finally:
        reset_language(token)

    body = body_of(sent[0])
    # with_language puts the instruction on the first system message.
    assert body["system"] == f"[agent: auditor]\nFirst.\n\n{instruction}\n\nSecond."
    assert body["messages"] == [{"role": "user", "content": "hi"}]


def test_without_a_system_message_the_field_is_left_out():
    provider, sent = make(claude_reply({"ok": True}))
    provider.complete([{"role": "user", "content": "hi"}])
    assert "system" not in body_of(sent[0])


def test_the_conversation_starts_with_the_user():
    # An audit's history opens with the Auditor's question.
    provider, sent = make(claude_reply({"ok": True}))
    provider.complete(
        [
            {"role": "system", "content": "s"},
            {"role": "assistant", "content": "What is a limit?"},
            {"role": "user", "content": "A value approached."},
        ]
    )
    assert body_of(sent[0])["messages"] == [
        {"role": "user", "content": "Begin."},
        {"role": "assistant", "content": "What is a limit?"},
        {"role": "user", "content": "A value approached."},
    ]


def test_a_prompt_with_only_a_system_message_still_has_a_user_turn():
    provider, sent = make(claude_reply({"ok": True}))
    provider.complete([{"role": "system", "content": "s"}])
    assert body_of(sent[0])["messages"] == [{"role": "user", "content": "Begin."}]


def test_the_conversation_never_ends_with_the_assistant():
    provider, sent = make(claude_reply({"ok": True}))
    provider.complete(
        [{"role": "user", "content": "hi"}, {"role": "assistant", "content": '{"action":'}]
    )
    messages = body_of(sent[0])["messages"]
    assert messages[-1] == {"role": "user", "content": "Continue."}
    assert [m["role"] for m in messages] == ["user", "assistant", "user"]


def test_blank_turns_are_left_out():
    # The API refuses an empty text block.
    provider, sent = make(claude_reply({"ok": True}))
    provider.complete([{"role": "user", "content": "  "}, {"role": "assistant", "content": "q"}, {"role": "user", "content": "a"}])
    assert [m["content"] for m in body_of(sent[0])["messages"]] == ["Begin.", "q", "a"]


def test_only_the_text_blocks_are_the_reply():
    reply = httpx.Response(
        200,
        json={
            "content": [
                {"type": "thinking", "thinking": "", "signature": "x"},
                {"type": "text", "text": '{"a": '},
                {"type": "text", "text": "1}"},
            ],
            "usage": {"input_tokens": 3, "output_tokens": 2},
        },
    )
    provider, _ = make(reply)
    assert provider.complete(MESSAGES) == '{"a": 1}'


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ('{"a": 1}', '{"a": 1}'),
        ('```json\n{"a": 1}\n```', '{"a": 1}'),
        ('Here is the verdict:\n{"a": {"b": [1, 2]}, "c": "}"}\nLet me know.', '{"a": {"b": [1, 2]}, "c": "}"}'),
        ('Sure.\n```json\n{"a": 1}\n```', '{"a": 1}'),
        ("The set {x} is empty, so: {\"a\": 1}", '{"a": 1}'),
        ("no json at all", "no json at all"),
        ('{"a": 1', '{"a": 1'),  # cut off: the caller's retry deals with it
    ],
)
def test_the_json_object_is_taken_out_of_the_text(text, expected):
    provider, _ = make(claude_reply(text))
    assert provider.complete(MESSAGES) == expected


def test_valid_json_is_never_cut():
    assert json_object('[{"a": 1}, {"b": 2}]') == '[{"a": 1}, {"b": 2}]'


def test_no_text_is_an_empty_response():
    for content in ([], [{"type": "text", "text": "  "}], [{"type": "thinking", "thinking": "hm"}]):
        provider, _ = make(httpx.Response(200, json={"content": content, "stop_reason": "refusal"}))
        with pytest.raises(ClaudeEmptyResponseError):
            provider.complete(MESSAGES)


def test_a_status_outside_2xx_is_an_api_error():
    error = {"type": "error", "error": {"type": "overloaded_error", "message": "Overloaded"}}
    provider, _ = make(httpx.Response(529, json=error))
    with pytest.raises(ClaudeAPIError, match="status=529.*Overloaded"):
        provider.complete(MESSAGES)


def test_the_configured_timeout_is_passed(monkeypatch):
    monkeypatch.setattr(settings, "llm_timeout_seconds", 12.5)
    seen = {}

    class Client:
        def post(self, url, **kwargs):
            seen.update(kwargs)
            return claude_reply({"ok": True})

    provider = ClaudeProvider()
    provider._client = Client()
    provider.complete(MESSAGES)
    assert seen["timeout"] == 12.5


# ---------------------------------------------------------------- which model


def test_the_model_is_the_one_passed_in_else_claude_model(monkeypatch):
    assert ClaudeProvider().model == "claude-haiku-5-5"
    assert ClaudeProvider("claude-opus-5-5").model == "claude-opus-5-5"
    monkeypatch.setattr(settings, "claude_model", "claude-sonnet-5-5")
    assert ClaudeProvider().model == "claude-sonnet-5-5"


def test_llm_model_is_claudes_only_when_llm_provider_is_claude(monkeypatch):
    monkeypatch.setattr(settings, "llm_model", "gpt-6-sol")
    monkeypatch.setattr(settings, "llm_provider", "openai")
    assert ClaudeProvider().model == "claude-haiku-5-5"
    monkeypatch.setattr(settings, "llm_provider", "")
    assert ClaudeProvider().model == "claude-haiku-5-5"

    monkeypatch.setattr(settings, "llm_provider", "claude")
    monkeypatch.setattr(settings, "llm_model", "claude-sonnet-5-5")
    assert ClaudeProvider().model == "claude-sonnet-5-5"
    assert get_provider().model == "claude-sonnet-5-5"


def test_claude_is_the_last_provider_chosen_by_key(monkeypatch):
    monkeypatch.setattr(settings, "anthropic_api_key", "k")
    assert get_provider().name == "claude"
    monkeypatch.setattr(settings, "gemini_api_key", "k")
    assert get_provider().name == "gemini"


def test_chosen_by_its_key_alone_claude_never_gets_llm_model(monkeypatch):
    # LLM_MODEL and the overrides were written for another provider.
    monkeypatch.setattr(settings, "anthropic_api_key", "k")
    monkeypatch.setattr(settings, "llm_model", "gpt-6-sol")
    monkeypatch.setattr(settings, "llm_model_overrides", '{"auditor": "gpt-6-sol"}')
    assert get_provider("auditor").model == "claude-haiku-5-5"

    monkeypatch.setattr(settings, "llm_provider", "claude")
    monkeypatch.setattr(settings, "llm_model_overrides", '{"auditor": "claude-opus-5-5"}')
    assert get_provider("auditor").model == "claude-opus-5-5"


# ---------------------------------------------------------------- the usage log


@pytest.fixture(name="logged")
def logged_fixture():
    """A request's context bound to an empty database; yields a function that reads the log."""
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    SQLModel.metadata.create_all(engine)
    token = usage.begin()
    usage.current().bind = engine

    def rows() -> list[LLMCall]:
        with Session(engine) as session:
            return list(session.exec(select(LLMCall).order_by(LLMCall.id)).all())

    yield rows
    usage.end(token)


def test_a_call_is_logged_with_its_tokens(logged):
    provider, _ = make(claude_reply({"ok": True}, fresh=120, cache_read=900, cache_write=80, output=45))
    provider.complete(MESSAGES)

    (row,) = logged()
    assert (row.provider, row.model, row.agent, row.ok) == ("claude", "claude-haiku-5-5", "auditor", True)
    # Every prompt token: the fresh ones, the ones read from the cache and the ones written to it.
    assert (row.input_tokens, row.cached_tokens, row.output_tokens) == (1100, 900, 45)
    assert row.audit_id is None and row.elapsed_ms >= 0 and row.created_at.tzinfo is not None


def test_failures_are_logged_without_tokens(logged):
    for reply, error in (
        (httpx.Response(500, text="boom"), ClaudeAPIError),
        (httpx.Response(200, json={"content": []}), ClaudeEmptyResponseError),
        (httpx.ConnectError("down"), httpx.ConnectError),
    ):
        provider, _ = make(reply)
        with pytest.raises(error):
            provider.complete([{"role": "user", "content": "hi"}])

    rows = logged()
    assert [(r.ok, r.input_tokens, r.output_tokens, r.agent) for r in rows] == [(False, 0, 0, "-")] * 3


def test_outside_a_request_nothing_is_logged():
    assert usage.current() is None
    provider, _ = make(claude_reply({"ok": True}, fresh=5, output=5))
    assert provider.complete(MESSAGES) == '{"ok": true}'
