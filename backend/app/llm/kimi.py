from app.config import settings
from app.llm.openai_compatible import OpenAICompatibleProvider


class KimiProvider(OpenAICompatibleProvider):
    name = "kimi"
    # Moonshot 的国内端点。用海外账号时把 base 换成 api.moonshot.ai。
    api_url = "https://api.moonshot.cn/v1/chat/completions"
    default_model = "moonshot-v1-8k"

    @property
    def _api_key(self) -> str:
        return settings.kimi_api_key
