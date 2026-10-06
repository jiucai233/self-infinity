import json
import re
from typing import Protocol, TypedDict


class Message(TypedDict):
    role: str  # "system" | "user" | "assistant"
    content: str


class LLMProvider(Protocol):
    name: str

    def complete(self, messages: list[Message]) -> str:
        """Return a raw text completion. Callers are responsible for parsing JSON out of it."""
        ...


# 每个子 agent 的 system prompt 第一行都是 "[agent: <name>]"。它有两个用途：日志里能
# 看出是哪个子 agent 在调用；Mock 靠它路由，而不是去匹配会随调优改动的提示词措辞。
_AGENT_TAG_RE = re.compile(r"^\[agent: ([a-z_]+)\]")


def agent_tag(agent: str) -> str:
    return f"[agent: {agent}]"


def agent_of(messages: list[Message]) -> str | None:
    system = next((m["content"] for m in messages if m["role"] == "system"), "")
    match = _AGENT_TAG_RE.match(system.lstrip())
    return match.group(1) if match else None


def fill_template(template: str, **values: str) -> str:
    """Fill `{name}` placeholders in one pass, so inserted text is never re-scanned.

    The templates are written for str.format (literal braces doubled); this keeps that
    convention but is safe for values that are JSON or user text full of braces.
    """
    pattern = re.compile("|".join("\\{" + re.escape(k) + "\\}" for k in values) + r"|\{\{|\}\}")

    def sub(match: re.Match) -> str:
        token = match.group(0)
        if token == "{{":
            return "{"
        if token == "}}":
            return "}"
        return values[token[1:-1]]

    return pattern.sub(sub, template)


def strip_code_fence(text: str) -> str:
    """去掉模型响应外层可能包裹的 ```json ... ``` 或 ``` ... ``` 代码块标记。

    所有真实 provider 共用这一逻辑，避免重复实现。
    """
    stripped = text.strip()
    if not stripped.startswith("```"):
        return stripped
    lines = stripped.splitlines()
    if len(lines) >= 2 and lines[-1].strip() == "```":
        lines = lines[1:-1]
    else:
        lines = lines[1:]
    return "\n".join(lines).strip()


JSON_RETRY_NOTICE = (
    "Your previous reply was not valid JSON. Reply with valid JSON only, "
    "with no extra text and no code fences."
)


def complete_with_json_retry(provider: LLMProvider, messages: list[Message]) -> str:
    """调用 provider.complete，若返回内容不是合法 JSON，追加一条纠错提示重试一次。

    重试后仍失败时原样返回第二次的结果，由调用方各自既有的兜底逻辑处理。
    """
    raw = provider.complete(messages)
    try:
        json.loads(raw)
        return raw
    except (json.JSONDecodeError, TypeError):
        retry_messages: list[Message] = [*messages, {"role": "user", "content": JSON_RETRY_NOTICE}]
        return provider.complete(retry_messages)
