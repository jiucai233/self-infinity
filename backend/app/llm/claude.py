"""Claude over the Anthropic Messages API.

Not OpenAI-compatible: the system prompt is a field of its own, the conversation must start
with the user and must not end with the assistant (current models reject a prefilled reply),
and there is no `response_format: json_object`, so the JSON object is taken out of the text.
"""

import json
import logging
import time

import httpx

from app.config import settings
from app.llm import usage
from app.llm.base import Message, agent_of, strip_code_fence, with_language

logger = logging.getLogger(__name__)

API_URL = "https://api.anthropic.com/v1/messages"
API_VERSION = "2023-06-01"
MAX_TOKENS = 16000
# Stand-ins where the API needs a user turn and the caller has none.
OPENING = "Begin."
CONTINUE = "Continue."


class ClaudeAPIError(RuntimeError):
    """The API answered with a status outside 2xx."""


class ClaudeEmptyResponseError(RuntimeError):
    """The reply has no text (no text block, or a refusal)."""


def json_object(text: str) -> str:
    """[text] when it is valid JSON; else the outermost `{...}` object in it (Claude sometimes
    writes a sentence around it); else [text] unchanged, for the caller's own fallback."""
    try:
        json.loads(text)
        return text
    except json.JSONDecodeError:
        pass
    decoder = json.JSONDecoder()
    start = text.find("{")
    while start != -1:
        try:
            _, end = decoder.raw_decode(text, start)
            return text[start:end]
        except json.JSONDecodeError:
            start = text.find("{", start + 1)
    return text


class ClaudeProvider:
    name = "claude"
    # The model get_provider(agent) resolved; None = the configured default below.
    _model: str | None = None

    def __init__(self, model: str | None = None) -> None:
        self._client = httpx.Client()
        self._model = model or None

    @property
    def model(self) -> str:
        # LLM_MODEL names a model of LLM_PROVIDER: it is Claude's only when that is claude.
        if self._model:
            return self._model
        if settings.llm_provider == "claude" and settings.llm_model:
            return settings.llm_model
        return settings.claude_model

    def _body(self, messages: list[Message]) -> dict:
        system = "\n\n".join(m["content"] for m in messages if m["role"] == "system" and m["content"].strip())
        turns = [
            {"role": m["role"], "content": m["content"]}
            for m in messages
            if m["role"] in ("user", "assistant") and m["content"].strip()
        ]
        if not turns or turns[0]["role"] == "assistant":
            turns.insert(0, {"role": "user", "content": OPENING})
        if turns[-1]["role"] == "assistant":
            turns.append({"role": "user", "content": CONTINUE})
        body: dict = {"model": self.model, "max_tokens": MAX_TOKENS, "messages": turns}
        if system:
            body["system"] = system
        return body

    def complete(self, messages: list[Message]) -> str:
        messages = with_language(messages)
        agent = agent_of(messages) or "-"
        model = self.model
        timeout = settings.llm_timeout_seconds

        def failed(elapsed_ms: float) -> None:
            usage.record(provider=self.name, model=model, agent=agent, elapsed_ms=elapsed_ms, ok=False)

        start = time.perf_counter()
        logger.info("claude complete() start agent=%s model=%s timeout_s=%.1f", agent, model, timeout)
        try:
            response = self._client.post(
                API_URL,
                json=self._body(messages),
                headers={
                    "x-api-key": settings.anthropic_api_key,
                    "anthropic-version": API_VERSION,
                    "content-type": "application/json",
                },
                timeout=timeout,
            )
        except Exception:
            elapsed_ms = (time.perf_counter() - start) * 1000
            logger.warning("claude complete() failed agent=%s after %.0fms", agent, elapsed_ms, exc_info=True)
            failed(elapsed_ms)
            raise

        elapsed_ms = (time.perf_counter() - start) * 1000

        if response.status_code < 200 or response.status_code >= 300:
            logger.warning(
                "claude complete() got status=%d agent=%s after %.0fms", response.status_code, agent, elapsed_ms
            )
            failed(elapsed_ms)
            raise ClaudeAPIError(f"claude call failed status={response.status_code} body={response.text[:500]}")

        data = response.json()
        text = "".join(
            block.get("text") or "" for block in data.get("content") or [] if block.get("type") == "text"
        )
        if not text.strip():
            logger.warning(
                "claude complete() returned no text agent=%s stop_reason=%s after %.0fms",
                agent, data.get("stop_reason"), elapsed_ms,
            )
            failed(elapsed_ms)
            raise ClaudeEmptyResponseError(f"claude returned no text (stop_reason={data.get('stop_reason')})")

        used = data.get("usage") or {}
        cached = used.get("cache_read_input_tokens") or 0
        # `input_tokens` is only the part that was neither read from nor written to the cache.
        prompt = (used.get("input_tokens") or 0) + cached + (used.get("cache_creation_input_tokens") or 0)
        logger.info(
            "claude complete() success agent=%s elapsed_ms=%.0f tokens=%s/%s",
            agent, elapsed_ms, prompt, used.get("output_tokens", "?"),
        )
        usage.record(
            provider=self.name,
            model=model,
            agent=agent,
            input_tokens=prompt,
            cached_tokens=cached,
            output_tokens=used.get("output_tokens"),
            elapsed_ms=elapsed_ms,
            ok=True,
        )
        return json_object(strip_code_fence(text))
