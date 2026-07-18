import pytest

from app.llm.gemini import GeminiEmptyResponseError, GeminiProvider


class _FakeResponse:
    def __init__(self, text: str | None) -> None:
        self.text = text


class _FakeModels:
    def __init__(self, text: str | None) -> None:
        self._text = text

    def generate_content(self, **kwargs):
        return _FakeResponse(self._text)


class _FakeClient:
    def __init__(self, text: str | None) -> None:
        self.models = _FakeModels(text)


def _make_provider(monkeypatch: pytest.MonkeyPatch, text: str | None) -> GeminiProvider:
    provider = GeminiProvider.__new__(GeminiProvider)
    provider._client = _FakeClient(text)
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
