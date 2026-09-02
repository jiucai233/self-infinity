from app.config import settings
from app.llm.base import LLMProvider
from app.llm.mock import MockProvider

_LOADERS = {}


def _load(name: str) -> LLMProvider:
    if name == "deepseek":
        from app.llm.deepseek import DeepSeekProvider

        return DeepSeekProvider()
    if name == "kimi":
        from app.llm.kimi import KimiProvider

        return KimiProvider()
    if name == "openai":
        from app.llm.openai import OpenAIProvider

        return OpenAIProvider()
    if name == "gemini":
        from app.llm.gemini import GeminiProvider

        return GeminiProvider()
    return MockProvider()


def get_provider() -> LLMProvider:
    """选择 LLM provider。

    LLM_PROVIDER 显式指定优先；否则按 key 是否配置自动选，顺序 deepseek > kimi >
    openai > gemini，都没配就用 MockProvider——离线永远能跑是这个项目一贯的约定。

    切换 provider 时记得同步改 LLM_MODEL（各家模型名不同），也要注意 M2 校准数字是
    绑定具体模型的：换了 provider 等于换了被测对象，校准要重跑。
    """
    if settings.llm_provider:
        return _load(settings.llm_provider)

    if settings.deepseek_api_key:
        return _load("deepseek")
    if settings.kimi_api_key:
        return _load("kimi")
    if settings.openai_api_key:
        return _load("openai")
    if settings.gemini_api_key:
        return _load("gemini")
    return MockProvider()
