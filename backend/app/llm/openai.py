from app.config import settings
from app.llm.openai_compatible import OpenAICompatibleProvider


class OpenAIProvider(OpenAICompatibleProvider):
    name = "openai"
    api_url = "https://api.openai.com/v1/chat/completions"
    default_model = "gpt-4o-mini"

    @property
    def _api_key(self) -> str:
        return settings.openai_api_key
