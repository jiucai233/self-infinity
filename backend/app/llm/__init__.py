from app.config import settings
from app.llm.base import LLMProvider
from app.llm.mock import MockProvider


def get_provider() -> LLMProvider:
    if settings.gemini_api_key:
        from app.llm.gemini import GeminiProvider

        return GeminiProvider()
    return MockProvider()
