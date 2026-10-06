"""LLM 与搜索 provider 的选择逻辑。

这两层是刻意正交的：换裁决模型不影响检索，换检索服务也不影响裁决。
"""

import pytest

from app.config import settings
from app.llm import get_provider
from app.llm.deepseek import DeepSeekProvider
from app.llm.kimi import KimiProvider
from app.llm.openai import OpenAIProvider
from app.llm.openai_compatible import OpenAICompatibleProvider
from app.search import get_search_provider


def test_no_keys_falls_back_to_mock():
    assert get_provider().name == "mock"


@pytest.mark.parametrize(
    ("key_field", "expected"),
    [
        ("deepseek_api_key", "deepseek"),
        ("kimi_api_key", "kimi"),
        ("openai_api_key", "openai"),
    ],
)
def test_a_single_key_selects_its_provider(monkeypatch, key_field, expected):
    monkeypatch.setattr(settings, key_field, "k")

    assert get_provider().name == expected


def test_explicit_setting_wins_over_configured_keys(monkeypatch):
    """配了 DeepSeek 的 key 但显式指定 kimi 时，以显式指定为准。"""
    monkeypatch.setattr(settings, "deepseek_api_key", "k")
    monkeypatch.setattr(settings, "kimi_api_key", "k")
    monkeypatch.setattr(settings, "llm_provider", "kimi")

    assert get_provider().name == "kimi"


def test_the_three_openai_compatible_providers_share_one_implementation():
    """它们只差 base URL 和 key —— 共用一份 HTTP 逻辑正是泛化的目的。"""
    for cls in (DeepSeekProvider, KimiProvider, OpenAIProvider):
        assert issubclass(cls, OpenAICompatibleProvider)
        assert cls.api_url.startswith("https://")

    urls = {DeepSeekProvider.api_url, KimiProvider.api_url, OpenAIProvider.api_url}
    assert len(urls) == 3


def test_deepseek_keeps_its_own_logger_name_after_generalisation():
    """日志按子类模块打，泛化不该让既有的日志过滤失效。"""
    provider = DeepSeekProvider.__new__(DeepSeekProvider)

    assert provider._logger.name == "app.llm.deepseek"


def test_search_provider_is_independent_of_the_llm_provider(monkeypatch):
    monkeypatch.setattr(settings, "deepseek_api_key", "k")

    assert get_provider().name == "deepseek"
    assert get_search_provider().name == "mock"


def test_search_key_selects_the_real_search_provider(monkeypatch):
    monkeypatch.setattr(settings, "tavily_api_key", "tvly-x")

    assert get_search_provider().name == "tavily"


# ---------------------------------------------------------------- plan 9.1：选择顺序与按子 agent 指定模型


def test_with_no_explicit_provider_the_first_configured_key_wins(monkeypatch):
    monkeypatch.setattr(settings, "gemini_api_key", "k")
    monkeypatch.setattr(settings, "openai_api_key", "k")

    assert get_provider().name == "openai"  # deepseek > kimi > openai > gemini


def test_an_explicit_mock_wins_over_every_configured_key(monkeypatch):
    monkeypatch.setattr(settings, "deepseek_api_key", "k")
    monkeypatch.setattr(settings, "llm_provider", "mock")

    assert get_provider().name == "mock"


def test_an_unknown_provider_name_falls_back_to_mock(monkeypatch):
    monkeypatch.setattr(settings, "llm_provider", "no-such-provider")

    assert get_provider().name == "mock"


def test_each_provider_has_its_own_default_model_when_none_is_configured():
    assert DeepSeekProvider().model == "deepseek-chat"
    assert KimiProvider().model
    assert OpenAIProvider().model
    assert len({DeepSeekProvider().model, KimiProvider().model, OpenAIProvider().model}) == 3


def test_llm_model_applies_to_every_sub_agent(monkeypatch):
    monkeypatch.setattr(settings, "deepseek_api_key", "k")
    monkeypatch.setattr(settings, "llm_model", "deepseek-reasoner")

    assert get_provider().model == "deepseek-reasoner"
    assert get_provider("auditor").model == "deepseek-reasoner"


def test_model_overrides_pick_a_model_per_sub_agent(monkeypatch):
    monkeypatch.setattr(settings, "deepseek_api_key", "k")
    monkeypatch.setattr(settings, "llm_model", "big-model")
    monkeypatch.setattr(settings, "llm_model_overrides", '{"clarifier": "small-model", "checkin_converter": "small-model"}')

    assert get_provider("clarifier").model == "small-model"
    assert get_provider("checkin_converter").model == "small-model"
    assert get_provider("auditor").model == "big-model"  # not overridden
    assert get_provider().model == "big-model"


def test_an_override_works_without_a_global_model(monkeypatch):
    monkeypatch.setattr(settings, "deepseek_api_key", "k")
    monkeypatch.setattr(settings, "llm_model_overrides", '{"planner": "deepseek-reasoner"}')

    assert get_provider("planner").model == "deepseek-reasoner"
    assert get_provider("auditor").model == "deepseek-chat"  # the provider's own default


@pytest.mark.parametrize("bad", ["not json", "[1, 2]", '"clarifier"', "null"])
def test_unusable_overrides_are_ignored_rather_than_breaking_startup(monkeypatch, bad):
    monkeypatch.setattr(settings, "deepseek_api_key", "k")
    monkeypatch.setattr(settings, "llm_model_overrides", bad)

    assert settings.parsed_model_overrides() == {}
    assert get_provider("clarifier").model == "deepseek-chat"


def test_the_mock_ignores_the_agent_and_the_model(monkeypatch):
    monkeypatch.setattr(settings, "llm_model_overrides", '{"clarifier": "x"}')

    assert get_provider("clarifier").name == "mock"


def test_the_request_body_carries_the_resolved_model():
    from tests.test_deepseek_provider import _content_response, _make_provider

    provider, client = _make_provider(_content_response('{"ok": true}'))
    provider._model = "small-model"
    messages = [{"role": "system", "content": "[agent: clarifier]\nx"}, {"role": "user", "content": "hi"}]

    provider.complete(messages)

    assert client.last_kwargs["json"]["model"] == "small-model"
    assert client.last_kwargs["json"]["messages"] == messages
