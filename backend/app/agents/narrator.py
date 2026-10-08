"""Narrator (plan 7.4): writes a short briefing from the Profile Builder's facts.

It describes; it does not advise, encourage or explain causes. Every number comes from the
facts (computed in code), the model only words them. Output is checked: not empty, at most
400 characters (a longer text is cut at a sentence end where possible).
"""

import json
import logging

from app.llm.base import LLMProvider, Message, agent_tag, complete_with_json_retry, fill_template
from app.schemas import ProfileFacts

logger = logging.getLogger(__name__)

MAX_NARRATIVE = 400

SYSTEM_PROMPT = (
    agent_tag("narrator")
    + """
Write a short briefing of the user's current learning state from the facts below.

Facts (JSON):
<facts>
{facts}
</facts>

Rules:
- Use only these facts. Never mention an audit, skill or number that is not in them.
- If a misconception cluster spans more than one skill, name those skills.
- Describe condition data as observations. You may state the user's own
  comparison when the facts include one, with its number of days, but never
  as a cause: "Because you slept less, you failed" is not allowed.
- No motivational language, no reassurance, no advice.
- 3 to 5 sentences, in English.

Output only JSON:
{{"narrative": "..."}}
"""
)


class NarratorError(Exception):
    """The Narrator's output is unusable."""


def _cut(text: str) -> str:
    if len(text) <= MAX_NARRATIVE:
        return text
    cut = text[:MAX_NARRATIVE]
    end = cut.rfind(".")
    return (cut[: end + 1] if end >= MAX_NARRATIVE // 2 else cut).rstrip()


class Narrator:
    def __init__(self, provider: LLMProvider):
        self._provider = provider

    def narrate(self, facts: ProfileFacts) -> str:
        # str.replace, not format: the facts are JSON and full of braces.
        system = fill_template(SYSTEM_PROMPT, facts=facts.model_dump_json(indent=1))
        messages: list[Message] = [
            {"role": "system", "content": system},
            {"role": "user", "content": "Write the briefing."},
        ]
        logger.info("narrator.narrate() calling provider=%s", self._provider.name)
        raw = complete_with_json_retry(self._provider, messages)
        try:
            narrative = json.loads(raw)["narrative"]
        except (json.JSONDecodeError, KeyError, TypeError) as exc:
            raise NarratorError("narrator output is not usable JSON") from exc
        if not isinstance(narrative, str) or not narrative.strip():
            raise NarratorError("narrator returned an empty narrative")
        return _cut(" ".join(narrative.split()))
