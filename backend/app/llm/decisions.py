"""OpenAI Decisions API: gpt-6-luna constrained to answers we define, about ten times faster
than a completion (~0.3 s). It returns a choice and a confidence, never text, so it only fits
calls whose answer is one of a fixed set — the front desk's intent is one.

Needs only the OpenAI key, whichever provider writes text. A failure raises DecisionsFailed;
callers fall back to their LLM path, so the short timeout is a latency cap, not a limit.
"""

import logging
import time

import httpx

from app.config import settings

logger = logging.getLogger(__name__)

URL = "https://api.openai.com/v1/decisions"
MODEL = "gpt-6-luna"
TIMEOUT_SECONDS = 5.0

# One client for the process: a warm connection is most of the speed (cold ~3 s, warm ~0.3 s).
_client = httpx.Client()


class DecisionsFailed(RuntimeError):
    """The call failed or came back in a shape we cannot read."""


def available() -> bool:
    return bool(settings.openai_api_key)


def choice(name: str, instructions: str, choices: list[tuple[str, str]]) -> dict:
    """A choice question; each choice is (value, description), an empty description is left out."""
    return {
        "type": "choice",
        "name": name,
        "instructions": instructions,
        "choices": [{"value": v, "description": d} if d else {"value": v} for v, d in choices],
    }


def decide(input_text: str, questions: list[dict]) -> dict[str, tuple[str, float]]:
    """Answers by question name: (choice, confidence). Raises DecisionsFailed."""
    if not available():
        raise DecisionsFailed("the OpenAI key is not configured")
    start = time.perf_counter()
    try:
        response = _client.post(
            URL,
            json={"model": MODEL, "input": input_text, "questions": questions},
            headers={"Authorization": f"Bearer {settings.openai_api_key}"},
            timeout=TIMEOUT_SECONDS,
        )
    except httpx.HTTPError as e:
        raise DecisionsFailed(f"could not reach OpenAI: {e}") from e
    elapsed_ms = (time.perf_counter() - start) * 1000
    if not 200 <= response.status_code < 300:
        raise DecisionsFailed(f"decisions failed status={response.status_code} body={response.text[:300]}")
    try:
        data = response.json()
        answers = {
            a["name"]: (str(a["choice"]), float(a.get("confidence", 0.0)))
            for a in data["answers"]
            if a.get("type") == "choice"
        }
    except (ValueError, KeyError, TypeError, AttributeError) as e:
        raise DecisionsFailed("decisions returned an unreadable answer") from e
    tokens = (data.get("usage") or {}).get("input_tokens", "?")
    logger.info("decisions answered in %.0fms tokens=%s %s", elapsed_ms, tokens, answers)
    return answers
