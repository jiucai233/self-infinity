import logging
import time

import pytest

from app.config import settings
from app.llm.gemini import GeminiEmptyResponseError, GeminiProvider, GeminiTimeoutError


class _FakeResponse:
    def __init__(self, text: str | None) -> None:
        self.text = text


class _FakeModels:
    def __init__(self, text: str | None, delay: float = 0.0) -> None:
        self._text = text
        self._delay = delay
        self.last_kwargs: dict | None = None

    def generate_content(self, **kwargs):
        self.last_kwargs = kwargs
        if self._delay:
            time.sleep(self._delay)
        return _FakeResponse(self._text)


class _FakeClient:
    def __init__(self, text: str | None, delay: float = 0.0) -> None:
        self.models = _FakeModels(text, delay=delay)


def _make_provider(monkeypatch: pytest.MonkeyPatch, text: str | None, delay: float = 0.0) -> GeminiProvider:
    provider = GeminiProvider.__new__(GeminiProvider)
    provider._client = _FakeClient(text, delay=delay)
    return provider


def test_complete_returns_plain_json(monkeypatch: pytest.MonkeyPatch):
    provider = _make_provider(monkeypatch, '{"action": "probe", "question": "为什么？"}')
    result = provider.complete([{"role": "system", "content": "sys"}, {"role": "user", "content": "hi"}])
    assert result == '{"action": "probe", "question": "为什么？"}'


def test_complete_strips_code_fence(monkeypatch: pytest.MonkeyPatch):
    fenced = '```json\n{"action": "probe", "question": "为什么？"}\n```'
    provider = _make_provider(monkeypatch, fenced)
    result = provider.complete([{"role": "system", "content": "sys"}, {"role": "user", "content": "hi"}])
    assert result == '{"action": "probe", "question": "为什么？"}'


def test_complete_strips_plain_code_fence_without_language(monkeypatch: pytest.MonkeyPatch):
    fenced = '```\n{"title": "t", "body": "b"}\n```'
    provider = _make_provider(monkeypatch, fenced)
    result = provider.complete([{"role": "system", "content": "sys"}, {"role": "user", "content": "hi"}])
    assert result == '{"title": "t", "body": "b"}'


def test_complete_raises_on_empty_text(monkeypatch: pytest.MonkeyPatch):
    provider = _make_provider(monkeypatch, None)
    with pytest.raises(GeminiEmptyResponseError):
        provider.complete([{"role": "system", "content": "sys"}, {"role": "user", "content": "hi"}])


def test_complete_raises_on_blank_text(monkeypatch: pytest.MonkeyPatch):
    provider = _make_provider(monkeypatch, "")
    with pytest.raises(GeminiEmptyResponseError):
        provider.complete([{"role": "system", "content": "sys"}, {"role": "user", "content": "hi"}])


def test_complete_passes_configured_timeout(monkeypatch: pytest.MonkeyPatch):
    """SDK 本身没有内建 timeout 机制（google-genai==0.3.0 的 HttpOptions 没有
    timeout 字段，底层 requests 调用也不传 timeout），所以 GeminiProvider 自己
    在应用层用线程池强制超时。这里只验证 settings.gemini_timeout_seconds 确实
    被读取并用于限制这次调用等待的时长，而不是被忽略。
    """
    monkeypatch.setattr(settings, "gemini_timeout_seconds", 0.05)
    provider = _make_provider(monkeypatch, '{"title": "t", "body": "b"}', delay=5.0)
    with pytest.raises(GeminiTimeoutError):
        provider.complete([{"role": "system", "content": "sys"}, {"role": "user", "content": "hi"}])


def test_complete_succeeds_when_within_timeout(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(settings, "gemini_timeout_seconds", 5.0)
    provider = _make_provider(monkeypatch, '{"title": "t", "body": "b"}')
    result = provider.complete([{"role": "system", "content": "sys"}, {"role": "user", "content": "hi"}])
    assert result == '{"title": "t", "body": "b"}'


def test_complete_logs_success(monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture):
    provider = _make_provider(monkeypatch, '{"title": "t", "body": "b"}')
    with caplog.at_level(logging.INFO, logger="app.llm.gemini"):
        provider.complete([{"role": "system", "content": "sys"}, {"role": "user", "content": "hi"}])
    assert any("success" in record.message for record in caplog.records)
