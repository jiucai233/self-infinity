from app.config import settings
from app.llm.base import LLMProvider
from app.llm.mock import MockProvider


def get_provider() -> LLMProvider:
    # 若两个 key 都配置了，DeepSeek 优先——它是后加入、目前打算实际启用的
    # provider；Gemini 仍保留作为已验证过的备选，需要切回时把
    # DEEPSEEK_API_KEY 留空即可。
    if settings.deepseek_api_key:
        from app.llm.deepseek import DeepSeekProvider

        return DeepSeekProvider()
    if settings.gemini_api_key:
        from app.llm.gemini import GeminiProvider

        return GeminiProvider()
    return MockProvider()
