import logging

from app.config import settings
from app.llm import usage
from app.llm.base import LLMProvider
from app.llm.mock import MockProvider

logger = logging.getLogger(__name__)

# 没有显式指定 LLM_PROVIDER 时，取第一个配了 key 的 provider，按这个顺序。
# Claude is last, so adding its key next to another one changes nothing by itself.
_KEY_ORDER = ("deepseek", "kimi", "openai", "gemini", "claude")
_KEY_FIELDS = {
    "deepseek": "deepseek_api_key",
    "kimi": "kimi_api_key",
    "openai": "openai_api_key",
    "gemini": "gemini_api_key",
    "claude": "anthropic_api_key",
}
# What an account can choose between (GET/PUT /api/llm).
CHOICES = ("openai", "claude")


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
    if name == "claude":
        from app.llm.claude import ClaudeProvider

        return ClaudeProvider(model=model)
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

    Inside a request the account's own choice (Profile.llm_provider, PUT /api/llm) wins when
    its key is configured. A choice other than the server's provider runs on that provider's
    own default model: LLM_MODEL and LLM_MODEL_OVERRIDES name the server provider's models.
    """
    server = selected_provider_name()
    chosen = account_provider_name()
    if chosen != server:
        return _load(chosen, own_default_model(chosen))
    return _load(server, _server_model(server, agent))


def has_key(name: str) -> bool:
    field = _KEY_FIELDS.get(name)
    return bool(field and getattr(settings, field))


def account_provider_name() -> str:
    """The provider this request's account runs on: its choice when that has a key, else the
    server's. Outside a request there is no choice."""
    server = selected_provider_name()
    # Nothing else to choose: no need to read the account's row.
    if not any(has_key(name) for name in CHOICES if name != server):
        return server
    choice = usage.account_choice()
    return choice if choice in CHOICES and has_key(choice) else server


def own_default_model(name: str) -> str:
    """The model one of CHOICES runs on when LLM_MODEL is not about it."""
    if name == "claude":
        return settings.claude_model
    from app.llm.openai import OpenAIProvider

    return OpenAIProvider.default_model


def default_model(name: str) -> str:
    """The model an agent without an override runs on with provider [name] (one of CHOICES)."""
    if name == selected_provider_name():
        return _server_model(name, None) or own_default_model(name)
    return own_default_model(name)


def _server_model(name: str, agent: str | None) -> str | None:
    # Claude chosen only because its key is the first one found: LLM_MODEL and the overrides
    # were written for another provider, and its model names must not reach Claude.
    if name == "claude" and settings.llm_provider != "claude":
        return None
    return settings.model_name_for(agent) or None
