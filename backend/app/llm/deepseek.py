import logging
import time

import httpx

from app.config import settings
from app.llm.base import Message, strip_code_fence

logger = logging.getLogger(__name__)

_API_URL = "https://api.deepseek.com/chat/completions"


class DeepSeekEmptyResponseError(RuntimeError):
    """DeepSeek 返回了空响应（没有 choices 或 message.content 为空）。"""


class DeepSeekAPIError(RuntimeError):
    """DeepSeek 接口返回了非 2xx 状态码。"""


class DeepSeekProvider:
    name = "deepseek"

    def __init__(self) -> None:
        self._client = httpx.Client()

    def complete(self, messages: list[Message]) -> str:
        # DeepSeek 走 OpenAI 兼容格式，role/content 可以直接透传，不像 Gemini
        # 那样需要把 system 单独拎出来、把 assistant 映射成 model。
        body = {
            "model": settings.llm_model,
            "messages": [{"role": m["role"], "content": m["content"]} for m in messages],
            "response_format": {"type": "json_object"},
        }

        start = time.perf_counter()
        logger.info(
            "deepseek complete() start model=%s timeout_s=%.1f",
            settings.llm_model,
            settings.deepseek_timeout_seconds,
        )
        try:
            response = self._client.post(
                _API_URL,
                json=body,
                headers={"Authorization": f"Bearer {settings.deepseek_api_key}"},
                timeout=settings.deepseek_timeout_seconds,
            )
        except Exception:
            elapsed_ms = (time.perf_counter() - start) * 1000
            logger.warning("deepseek complete() failed after %.0fms", elapsed_ms, exc_info=True)
            raise

        elapsed_ms = (time.perf_counter() - start) * 1000

        if response.status_code < 200 or response.status_code >= 300:
            logger.warning(
                "deepseek complete() got status=%d after %.0fms", response.status_code, elapsed_ms
            )
            snippet = response.text[:500]
            raise DeepSeekAPIError(f"DeepSeek 调用失败 status={response.status_code} body={snippet}")

        data = response.json()
        choices = data.get("choices") or []
        content = choices[0]["message"]["content"] if choices else None
        if not content:
            logger.warning("deepseek complete() returned empty content after %.0fms", elapsed_ms)
            raise DeepSeekEmptyResponseError("DeepSeek 返回了空响应")

        logger.info("deepseek complete() success elapsed_ms=%.0f", elapsed_ms)
        return strip_code_fence(content)
