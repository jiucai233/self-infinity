"""OpenAI 兼容接口的通用实现。

DeepSeek、OpenAI、Kimi(Moonshot) 用的是同一套 `/chat/completions` 协议:一样的
role/content 消息结构、一样的 `response_format: json_object`、一样的
`choices[0].message.content` 响应形状。区别只有 base URL、api key 和模型名。

所以它们共用这个基类,子类只声明"我是谁、打哪个地址、用哪把 key"。换模型提供商因此
是加一个十行的子类,而不是复制一份 HTTP 逻辑。Gemini 不在此列——它的消息格式和
system 处理方式都不同,单独实现。
"""

import logging
import time

import httpx

from app.config import settings
from app.llm.base import Message, strip_code_fence


class OpenAICompatibleAPIError(RuntimeError):
    """接口返回了非 2xx 状态码。"""


class OpenAICompatibleEmptyResponseError(RuntimeError):
    """接口返回了空响应(没有 choices 或 message.content 为空)。"""


class OpenAICompatibleProvider:
    name = "openai-compatible"
    api_url = ""

    def __init__(self) -> None:
        self._client = httpx.Client()

    @property
    def _api_key(self) -> str:
        raise NotImplementedError

    @property
    def _timeout(self) -> float:
        raise NotImplementedError

    @property
    def _logger(self) -> logging.Logger:
        # 按**子类所在模块**取 logger,而不是本模块——这样 DeepSeek 的日志仍然打在
        # app.llm.deepseek 下,已有的日志过滤和测试断言不受泛化影响。
        return logging.getLogger(type(self).__module__)

    def complete(self, messages: list[Message]) -> str:
        logger = self._logger
        body = {
            "model": settings.llm_model,
            "messages": [{"role": m["role"], "content": m["content"]} for m in messages],
            "response_format": {"type": "json_object"},
        }

        start = time.perf_counter()
        logger.info(
            "%s complete() start model=%s timeout_s=%.1f", self.name, settings.llm_model, self._timeout
        )
        try:
            response = self._client.post(
                self.api_url,
                json=body,
                headers={"Authorization": f"Bearer {self._api_key}"},
                timeout=self._timeout,
            )
        except Exception:
            elapsed_ms = (time.perf_counter() - start) * 1000
            logger.warning("%s complete() failed after %.0fms", self.name, elapsed_ms, exc_info=True)
            raise

        elapsed_ms = (time.perf_counter() - start) * 1000

        if response.status_code < 200 or response.status_code >= 300:
            logger.warning(
                "%s complete() got status=%d after %.0fms", self.name, response.status_code, elapsed_ms
            )
            raise OpenAICompatibleAPIError(
                f"{self.name} 调用失败 status={response.status_code} body={response.text[:500]}"
            )

        data = response.json()
        choices = data.get("choices") or []
        content = choices[0]["message"]["content"] if choices else None
        if not content:
            logger.warning("%s complete() returned empty content after %.0fms", self.name, elapsed_ms)
            raise OpenAICompatibleEmptyResponseError(f"{self.name} 返回了空响应")

        logger.info("%s complete() success elapsed_ms=%.0f", self.name, elapsed_ms)
        return strip_code_fence(content)
