from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env")

    gemini_api_key: str = ""
    deepseek_api_key: str = ""
    openai_api_key: str = ""
    kimi_api_key: str = ""
    # 显式指定用哪个 provider（"deepseek" / "openai" / "kimi" / "gemini" / "mock"）。
    # 留空则按 key 是否配置自动选择，见 app/llm/__init__.py。配了多把 key 又想
    # 临时切换时用它，比删 key 方便。
    llm_provider: str = ""
    # llm_model 被 Gemini 与 DeepSeek 共用同一个字段——两者不会同时启用（见
    # get_provider() 的优先级选择），所以不需要各自独立的 model 字段，只需要
    # 部署时按当前启用的 provider 把 LLM_MODEL 设成对应的值（如 "deepseek-chat"）。
    llm_model: str = "gemini-2.5-flash"
    database_url: str = "sqlite:///./self_infinity.db"
    # 这两个数字不再是"审计官的额度"——2026-07-19 起 Auditor 的系统提示词里已经不
    # 告诉模型有多少轮可用，真正"什么时候该收敛"完全由模型自己判断（听懂了/发现
    # 讲不清楚的地方就裁决，不为了凑轮次硬问）。这两个值只是一道服务端安全阀，
    # 防止模型异常时（比如顽固地一直 probe）无限问下去，正常对话几乎不会真的碰到
    # 这个上限，所以数值定得比"预期轮数"宽松很多。night 模式在此基础上再翻倍
    # （见 app/routers/audits.py 的 _resolve_max_turns）。
    audit_max_turns: int = 8
    task_max_turns: int = 4
    # Challenger（审计复核官）总开关。留成配置项是为了 M2 校准能跑
    # 单 Auditor vs Auditor+Challenger 的消融对比——见 eval/run_calibration.py。
    challenger_enabled: bool = True
    # 注入 Challenger 的历史 misconception 条数上限。取最近的若干条即可：
    # 全量注入会让 prompt 随使用时长无限膨胀，而越久远的错误模型越可能已经被纠正。
    challenger_misconception_limit: int = 5
    # 搜索是独立于 LLM provider 的一层（见 app/search/base.py 的模块注释）：
    # 换裁决模型不影响检索，换检索服务也不影响裁决。留空则用离线替身。
    tavily_api_key: str = ""
    search_timeout_seconds: float = 15.0
    # OpenAI / Kimi 共用；DeepSeek 沿用自己那个字段，避免改动既有部署的 .env。
    llm_timeout_seconds: float = 30.0
    gemini_timeout_seconds: float = 30.0
    deepseek_timeout_seconds: float = 30.0


settings = Settings()
