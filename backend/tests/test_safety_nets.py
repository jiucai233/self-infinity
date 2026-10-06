"""测试环境的两道保险：没有真 key、没有外网。（见 conftest.py）

一个测试里调了 monkeypatch.undo() 就曾让后面的调用悄悄落到真实的 DeepSeek 上，所以这两道
保险不依赖测试自己的 monkeypatch。
"""

import socket

import pytest

from app.config import settings
from app.llm import get_provider


def test_no_real_key_is_visible_to_a_test():
    assert not any(
        [settings.deepseek_api_key, settings.gemini_api_key, settings.openai_api_key, settings.kimi_api_key]
    )
    assert settings.llm_provider == "" and settings.tavily_api_key == ""
    assert get_provider("recorder").name == "mock"


def test_real_hosts_cannot_be_resolved_or_reached():
    with pytest.raises(AssertionError, match="real host"):
        socket.getaddrinfo("api.deepseek.com", 443)
    with pytest.raises(AssertionError):
        socket.create_connection(("api.tavily.com", 443), timeout=1)


def test_loopback_stays_open():
    assert socket.getaddrinfo("127.0.0.1", 8000)


def test_undoing_the_tests_own_monkeypatch_lifts_neither_safety_net(monkeypatch):
    monkeypatch.setattr(settings, "llm_provider", "mock")
    monkeypatch.undo()

    assert not settings.deepseek_api_key
    assert get_provider("recorder").name == "mock"
    with pytest.raises(AssertionError):
        socket.getaddrinfo("api.deepseek.com", 443)
