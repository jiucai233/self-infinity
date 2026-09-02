from app.config import settings
from app.llm.openai_compatible import (
    OpenAICompatibleAPIError,
    OpenAICompatibleEmptyResponseError,
    OpenAICompatibleProvider,
)

# DeepSeek 走的就是标准 OpenAI 兼容协议，实现全在基类里（见 openai_compatible.py）。
# 这两个别名保留原名字，调用方和既有测试不用跟着改。
DeepSeekAPIError = OpenAICompatibleAPIError
DeepSeekEmptyResponseError = OpenAICompatibleEmptyResponseError


class DeepSeekProvider(OpenAICompatibleProvider):
    name = "deepseek"
    api_url = "https://api.deepseek.com/chat/completions"

    @property
    def _api_key(self) -> str:
        return settings.deepseek_api_key

    @property
    def _timeout(self) -> float:
        return settings.deepseek_timeout_seconds
