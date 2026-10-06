import logging

from app.config import settings
from app.llm.base import LLMProvider
from app.llm.mock import MockProvider

logger = logging.getLogger(__name__)

# 没有显式指定 LLM_PROVIDER 时，取第一个配了 key 的 provider，按这个顺序。
_KEY_ORDER = ("deepseek", "kimi", "openai", "gemini")
_KEY_FIELDS = {
    "deepseek": "deepseek_api_key",
    "kimi": "kimi_api_key",
    "openai": "openai_api_key",
    "gemini": "gemini_api_key",
}


def _load(name: str, model: str | None) -> LLMProvider:
    if name == "deepseek":
        from app.llm.deepseek import DeepSeekProvider

        return DeepSeekProvider(model=model)
    if name == "kimi":
        from app.llm.kimi import KimiProvider

        return KimiProvider(model=model)
    if name == "openai":
        from app.llm.openai import OpenAIProvider

        return OpenAIProvider(model=model)
    if name == "gemini":
        from app.llm.gemini import GeminiProvider

        return GeminiProvider(model=model)
    if name != "mock":
        logger.warning("unknown LLM_PROVIDER=%r, falling back to the mock provider", name)
    return MockProvider()


def selected_provider_name() -> str:
    """Explicit LLM_PROVIDER, else the first provider with a key, else mock."""
    if settings.llm_provider:
        return settings.llm_provider
    for name in _KEY_ORDER:
        if getattr(settings, _KEY_FIELDS[name]):
            return name
    return "mock"


def get_provider(agent: str | None = None) -> LLMProvider:
    """Provider for one sub-agent.

    `agent` is the sub-agent's name ("planner", "auditor", ...): it picks the model
    from LLM_MODEL_OVERRIDES, falling back to LLM_MODEL and then to the provider's
    own default. Cheap sub-agents (Clarifier, Check-in Converter) can run on a small
    model while the Planner, Auditor and Challenger keep the strongest one.

    The mock ignores the agent. 离线永远能跑是这个项目一贯的约定——没有任何 key 就是 mock。

    切换 provider 时要注意校准数字是绑定具体模型的：换了 provider 等于换了被测对象。
    """
    return _load(selected_provider_name(), settings.model_name_for(agent) or None)
