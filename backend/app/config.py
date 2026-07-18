from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env")

    gemini_api_key: str = ""
    llm_model: str = "gemini-2.5-flash"
    database_url: str = "sqlite:///./self_infinity.db"
    audit_max_turns: int = 4
    task_max_turns: int = 2
    gemini_timeout_seconds: float = 30.0


settings = Settings()
