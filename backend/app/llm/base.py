import json
from typing import Protocol, TypedDict


class Message(TypedDict):
    role: str  # "system" | "user" | "assistant"
    content: str


class LLMProvider(Protocol):
    name: str

    def complete(self, messages: list[Message]) -> str:
        """Return a raw text completion. Callers are responsible for parsing JSON out of it."""
        ...


_JSON_RETRY_NOTICE = "上一次的回复不是合法 JSON，请只输出合法 JSON，不要有任何额外文字或代码块标记。"


def complete_with_json_retry(provider: LLMProvider, messages: list[Message]) -> str:
    """调用 provider.complete，若返回内容不是合法 JSON，追加一条纠错提示重试一次。

    重试后仍失败时原样返回第二次的结果，由调用方各自既有的兜底逻辑处理。
    """
    raw = provider.complete(messages)
    try:
        json.loads(raw)
        return raw
    except (json.JSONDecodeError, TypeError):
        retry_messages: list[Message] = [*messages, {"role": "user", "content": _JSON_RETRY_NOTICE}]
        return provider.complete(retry_messages)
