import json
import logging

import pytest

from app.config import settings
from app.llm.deepseek import DeepSeekAPIError, DeepSeekEmptyResponseError, DeepSeekProvider


class _FakeResponse:
    def __init__(self, status_code: int, payload: dict | None = None, text: str = "") -> None:
        self.status_code = status_code
        self._payload = payload
        self.text = text or json.dumps(payload) if payload is not None else text

    def json(self) -> dict:
        return self._payload


class _FakeClient:
    def __init__(self, response: _FakeResponse) -> None:
        self._response = response
        self.last_kwargs: dict | None = None

    def post(self, url, **kwargs):
        self.last_kwargs = {"url": url, **kwargs}
        return self._response


def _make_provider(response: _FakeResponse) -> tuple[DeepSeekProvider, _FakeClient]:
    provider = DeepSeekProvider.__new__(DeepSeekProvider)
    fake_client = _FakeClient(response)
    provider._client = fake_client
    return provider, fake_client


def _content_response(content: str) -> _FakeResponse:
    return _FakeResponse(200, {"choices": [{"message": {"content": content}}]})


def test_complete_returns_plain_json():
    provider, _ = _make_provider(_content_response('{"action": "probe", "question": "为什么？"}'))
    result = provider.complete([{"role": "system", "content": "sys"}, {"role": "user", "content": "hi"}])
    assert result == '{"action": "probe", "question": "为什么？"}'


def test_complete_strips_code_fence():
    fenced = '```json\n{"action": "probe", "question": "为什么？"}\n```'
    provider, _ = _make_provider(_content_response(fenced))
    result = provider.complete([{"role": "system", "content": "sys"}, {"role": "user", "content": "hi"}])
    assert result == '{"action": "probe", "question": "为什么？"}'


def test_complete_raises_on_missing_choices():
    provider, _ = _make_provider(_FakeResponse(200, {"choices": []}))
    with pytest.raises(DeepSeekEmptyResponseError):
        provider.complete([{"role": "system", "content": "sys"}, {"role": "user", "content": "hi"}])


def test_complete_raises_on_empty_content():
    provider, _ = _make_provider(_content_response(""))
    with pytest.raises(DeepSeekEmptyResponseError):
        provider.complete([{"role": "system", "content": "sys"}, {"role": "user", "content": "hi"}])


def test_complete_raises_on_non_2xx_status():
    provider, _ = _make_provider(_FakeResponse(500, text="internal error"))
    with pytest.raises(DeepSeekAPIError):
        provider.complete([{"role": "system", "content": "sys"}, {"role": "user", "content": "hi"}])


def test_complete_passes_configured_timeout(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(settings, "deepseek_timeout_seconds", 12.5)
    provider, fake_client = _make_provider(_content_response('{"title": "t", "body": "b"}'))
    provider.complete([{"role": "system", "content": "sys"}, {"role": "user", "content": "hi"}])
    assert fake_client.last_kwargs["timeout"] == 12.5


def test_complete_logs_success(caplog: pytest.LogCaptureFixture):
    provider, _ = _make_provider(_content_response('{"title": "t", "body": "b"}'))
    with caplog.at_level(logging.INFO, logger="app.llm.deepseek"):
        provider.complete([{"role": "system", "content": "sys"}, {"role": "user", "content": "hi"}])
    assert any("success" in record.message for record in caplog.records)
