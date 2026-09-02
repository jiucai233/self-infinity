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
