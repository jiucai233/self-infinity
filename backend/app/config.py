from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env")

    gemini_api_key: str = ""
    deepseek_api_key: str = ""
    # llm_model 被 Gemini 与 DeepSeek 共用同一个字段——两者不会同时启用（见
    # get_provider() 的优先级选择），所以不需要各自独立的 model 字段，只需要
    # 部署时按当前启用的 provider 把 LLM_MODEL 设成对应的值（如 "deepseek-chat"）。
    llm_model: str = "gemini-2.5-flash"
    database_url: str = "sqlite:///./self_infinity.db"
    audit_max_turns: int = 4
    task_max_turns: int = 2
    gemini_timeout_seconds: float = 30.0
    deepseek_timeout_seconds: float = 30.0


settings = Settings()
