"""配置（plan 9.1）：16 个环境变量及其默认值。"""

import pytest

from app.config import Settings

ENV_NAMES = [
    "LLM_PROVIDER", "LLM_MODEL", "LLM_MODEL_OVERRIDES", "DEEPSEEK_API_KEY", "GEMINI_API_KEY", "OPENAI_API_KEY",
    "KIMI_API_KEY", "TAVILY_API_KEY", "DATABASE_URL", "APP_TIMEZONE", "AUDIT_MAX_TURNS", "TASK_MAX_TURNS",
    "CHALLENGER_ENABLED", "CHALLENGER_MISCONCEPTION_LIMIT", "LLM_TIMEOUT_SECONDS", "SEARCH_TIMEOUT_SECONDS",
    "AUTH_MODE", "SUPABASE_URL", "SUPABASE_JWT_SECRET", "TRANSCRIBE_MODEL", "SPEECH_MODEL", "SPEECH_VOICE",
    "REALTIME_MODEL", "LIVE_TRANSCRIBE_MODEL",
]


@pytest.fixture(name="clean_env")
def clean_env_fixture(monkeypatch):
    for name in ENV_NAMES + ["POSTGRES_URL", "VERCEL"]:
        monkeypatch.delenv(name, raising=False)


def test_defaults_match_the_plan(clean_env):
    s = Settings(_env_file=None)

    assert (s.llm_provider, s.llm_model, s.llm_model_overrides) == ("", "", "")
    assert (s.deepseek_api_key, s.gemini_api_key, s.openai_api_key, s.kimi_api_key, s.tavily_api_key) == ("",) * 5
    assert s.database_url == "sqlite:///./self_infinity.db"
    assert s.app_timezone == "Asia/Seoul"
    assert (s.audit_max_turns, s.task_max_turns) == (8, 4)
    assert s.challenger_enabled is True
    assert s.challenger_misconception_limit == 5
    assert (s.llm_timeout_seconds, s.search_timeout_seconds) == (90, 15)
    assert (s.auth_mode, s.supabase_url, s.supabase_jwt_secret) == ("dev", "", "")


def test_every_variable_in_the_plan_is_a_setting(clean_env):
    fields = {name.lower() for name in Settings.model_fields}

    assert {name.lower() for name in ENV_NAMES} <= fields


def test_values_come_from_the_environment(clean_env, monkeypatch):
    monkeypatch.setenv("LLM_PROVIDER", "kimi")
    monkeypatch.setenv("APP_TIMEZONE", "UTC")
    monkeypatch.setenv("AUDIT_MAX_TURNS", "6")
    monkeypatch.setenv("CHALLENGER_ENABLED", "false")
    monkeypatch.setenv("LLM_MODEL_OVERRIDES", '{"clarifier": "tiny"}')

    s = Settings(_env_file=None)

    assert (s.llm_provider, s.app_timezone, s.audit_max_turns, s.challenger_enabled) == ("kimi", "UTC", 6, False)
    assert s.model_name_for("clarifier") == "tiny"
    assert s.model_name_for("auditor") == ""  # no global model either: the provider's default applies


def test_empty_values_mean_the_default_so_the_example_file_can_be_copied_as_is(clean_env, monkeypatch):
    for name in ENV_NAMES:
        monkeypatch.setenv(name, "")

    s = Settings(_env_file=None)

    assert (s.audit_max_turns, s.challenger_enabled, s.database_url) == (8, True, "sqlite:///./self_infinity.db")


def test_an_env_file_with_unknown_leftovers_does_not_break_startup(clean_env, tmp_path):
    env_file = tmp_path / ".env"
    env_file.write_text("DEEPSEEK_TIMEOUT_SECONDS=12\nSOMETHING_REMOVED=1\nLLM_MODEL=x\n")

    assert Settings(_env_file=env_file).llm_model == "x"


def test_the_example_env_file_lists_every_setting():
    from pathlib import Path

    example = (Path(__file__).resolve().parent.parent / ".env.example").read_text()
    listed = {line.split("=")[0] for line in example.splitlines() if "=" in line and not line.startswith("#")}

    assert listed == set(ENV_NAMES)


# ---------------------------------------------------------------- Vercel + Supabase integration


def test_the_supabase_integrations_postgres_url_is_the_database(clean_env, monkeypatch):
    monkeypatch.setenv("POSTGRES_URL", "postgres://from-integration")
    assert Settings(_env_file=None).database_url == "postgres://from-integration"

    monkeypatch.setenv("DATABASE_URL", "postgres://explicit")
    assert Settings(_env_file=None).database_url == "postgres://explicit"


def test_auth_defaults_to_supabase_on_vercel_and_dev_elsewhere(clean_env, monkeypatch):
    assert Settings(_env_file=None).auth_mode == "dev"

    monkeypatch.setenv("VERCEL", "1")
    assert Settings(_env_file=None).auth_mode == "supabase"

    monkeypatch.setenv("AUTH_MODE", "dev")
    assert Settings(_env_file=None).auth_mode == "dev"


def test_postgres_urls_lose_the_tags_libpq_does_not_know(monkeypatch):
    from app.db import _make_engine

    monkeypatch.delenv("VERCEL", raising=False)
    eng = _make_engine("postgres://u:p@host:6543/postgres?sslmode=require&supa=base-pooler.x&pgbouncer=true")

    assert eng.url.drivername == "postgresql+psycopg"
    assert dict(eng.url.query) == {"sslmode": "require"}


def test_sqlite_is_refused_on_vercel_with_a_readable_error(monkeypatch):
    from app.db import _make_engine

    monkeypatch.setenv("VERCEL", "1")
    with pytest.raises(RuntimeError, match="POSTGRES_URL"):
        _make_engine("sqlite:///./self_infinity.db")
