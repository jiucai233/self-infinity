import json
import logging
import os

from pydantic import AliasChoices, Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

logger = logging.getLogger(__name__)


class Settings(BaseSettings):
    """All settings come from environment variables / `.env` (plan section 9.1)."""

    # extra="ignore": 旧版 .env 里可能还留着已经删掉的变量，不该因此启动失败。
    # env_ignore_empty: .env.example 里的值全是空的，直接复制成 .env 也要能用——空值等于
    # "用默认值"，而不是把数字、布尔字段解析成空字符串。
    model_config = SettingsConfigDict(env_file=".env", extra="ignore", env_ignore_empty=True)

    # deepseek / openai / kimi / gemini / mock。留空则按 key 是否配置自动选择
    # （第一个配了 key 的 provider），都没配就用 mock，见 app/llm/__init__.py。
    llm_provider: str = ""
    # 所选 provider 的默认模型；留空则用该 provider 自己的默认值。
    llm_model: str = ""
    # 按子 agent 单独指定模型，JSON，例如 {"clarifier": "deepseek-chat"}。
    # 简单的 agent（Clarifier、Check-in Converter）可以用小模型，判断类的用最强的。
    llm_model_overrides: str = ""
    deepseek_api_key: str = ""
    gemini_api_key: str = ""
    openai_api_key: str = ""
    kimi_api_key: str = ""
    # 留空则用离线搜索替身。搜索是独立于 LLM provider 的一层，互不影响。
    tavily_api_key: str = ""
    # POSTGRES_URL is what the Vercel ↔ Supabase integration sets (the transaction pooler);
    # DATABASE_URL wins when both are there.
    database_url: str = Field(
        "sqlite:///./self_infinity.db", validation_alias=AliasChoices("database_url", "postgres_url")
    )
    # dev：不登录，所有请求都是同一个本地用户（本地开发、测试、离线演示）。
    # supabase：每个请求必须带 Supabase 的 access token（Authorization: Bearer ...），
    # 每个账号的数据放在自己的 schema 里（见 app/db.py）。
    # 留空：在 Vercel 上（有 VERCEL 环境变量）是 supabase，别处是 dev——公开的网站
    # 不该默认成"谁都是同一个本地用户"。
    auth_mode: str = ""
    # Supabase 项目地址，例如 https://abcd.supabase.co；用它的 JWKS 验证 token。
    supabase_url: str = ""
    # 旧项目用 HS256 共享密钥签 token 时才需要（Project Settings → API → JWT Secret）。
    supabase_jwt_secret: str = ""
    # 显示时区，也是 DailyCheckIn.date 这类"一天一条"的日历日期的分界。
    app_timezone: str = "Asia/Seoul"
    # 这两个数字只是服务端的安全阀：prompt 里不告诉模型还剩几轮，"什么时候该收敛"
    # 由模型自己判断。night 模式在此基础上翻倍（见 app/services/audit_flow.py）。
    audit_max_turns: int = 8
    task_max_turns: int = 4
    # Challenger 总开关；留成配置项是为了评估时能做 Auditor 单独 vs Auditor+Challenger 的消融。
    challenger_enabled: bool = True
    # 注入 Challenger 的历史 misconception 条数上限，取最近的若干条。
    challenger_misconception_limit: int = 5
    llm_timeout_seconds: float = 30.0
    search_timeout_seconds: float = 15.0

    @model_validator(mode="after")
    def _default_auth_mode(self) -> "Settings":
        if not self.auth_mode:
            self.auth_mode = "supabase" if os.environ.get("VERCEL") else "dev"
        return self

    def parsed_model_overrides(self) -> dict[str, str]:
        if not self.llm_model_overrides.strip():
            return {}
        try:
            data = json.loads(self.llm_model_overrides)
        except json.JSONDecodeError:
            logger.warning("LLM_MODEL_OVERRIDES is not valid JSON, ignoring it")
            return {}
        if not isinstance(data, dict):
            logger.warning("LLM_MODEL_OVERRIDES must be a JSON object, ignoring it")
            return {}
        return {str(k): str(v) for k, v in data.items() if v}

    def model_name_for(self, agent: str | None) -> str:
        """Model configured for a sub-agent; empty means "the provider's default"."""
        if agent:
            override = self.parsed_model_overrides().get(agent)
            if override:
                return override
        return self.llm_model


settings = Settings()
