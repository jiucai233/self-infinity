import logging
import time
from concurrent.futures import ThreadPoolExecutor
from concurrent.futures import TimeoutError as FutureTimeoutError

from google import genai

from app.config import settings
from app.llm.base import Message, strip_code_fence

logger = logging.getLogger(__name__)


class GeminiEmptyResponseError(RuntimeError):
    """Gemini 返回了空响应，例如被安全过滤器拦截。"""


class GeminiTimeoutError(RuntimeError):
    """Gemini 调用超过 settings.gemini_timeout_seconds 仍未返回。

    注意：pinned 的 google-genai==0.3.0 SDK 本身不支持任何超时配置——它的
    HttpOptions 只有 base_url/api_version/headers/response_payload，底层
    requests.Session().send() 调用也没有传 timeout（见
    google/genai/_api_client.py 的 _request_unauthorized），是真正无界阻塞。
    所以这里用线程池在应用层强制加一个超时上限，而不是指望 SDK 的 config 参数。
    """


class GeminiProvider:
    name = "gemini"

    def __init__(self) -> None:
        self._client = genai.Client(api_key=settings.gemini_api_key)

    def complete(self, messages: list[Message]) -> str:
        system = "\n".join(m["content"] for m in messages if m["role"] == "system")
        turns = [m for m in messages if m["role"] != "system"]
        contents = [
            {"role": "model" if m["role"] == "assistant" else "user", "parts": [{"text": m["content"]}]}
            for m in turns
        ]

        start = time.perf_counter()
        logger.info(
            "gemini complete() start model=%s timeout_s=%.1f",
            settings.llm_model,
            settings.gemini_timeout_seconds,
        )
        try:
            response = self._generate_with_timeout(contents, system)
        except FutureTimeoutError:
            elapsed_ms = (time.perf_counter() - start) * 1000
            logger.error(
                "gemini complete() timed out after %.0fms (limit=%.1fs)",
                elapsed_ms,
                settings.gemini_timeout_seconds,
            )
            raise GeminiTimeoutError(
                f"Gemini 调用超过 {settings.gemini_timeout_seconds}s 未返回"
            ) from None
        except Exception:
            elapsed_ms = (time.perf_counter() - start) * 1000
            logger.warning("gemini complete() failed after %.0fms", elapsed_ms, exc_info=True)
            raise

        elapsed_ms = (time.perf_counter() - start) * 1000
        text = response.text
        if not text:
            logger.warning("gemini complete() returned empty text after %.0fms", elapsed_ms)
            raise GeminiEmptyResponseError("Gemini 返回了空响应，可能被安全过滤器拦截")

        logger.info("gemini complete() success elapsed_ms=%.0f", elapsed_ms)
        return strip_code_fence(text)

    def _generate_with_timeout(self, contents: list[dict], system: str):
        executor = ThreadPoolExecutor(max_workers=1)
        try:
            future = executor.submit(
                self._client.models.generate_content,
                model=settings.llm_model,
                contents=contents,
                config={
                    "system_instruction": system,
                    "response_mime_type": "application/json",
                },
            )
            return future.result(timeout=settings.gemini_timeout_seconds)
        finally:
            # wait=False：超时后不阻塞等待后台线程结束，让它自然收尾（SDK 本身
            # 不提供取消正在进行的 HTTP 请求的方式）。
            executor.shutdown(wait=False)
