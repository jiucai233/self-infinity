"""Front desk (contract section 5): classifies one chat message into an intent.

It only classifies and words a short reply. It never runs anything: code does that
(app/services/chat.py, AD-7). Output is parsed defensively; anything unusable raises
FrontDeskError, which the chat endpoint turns into a 502.
"""

import json
import logging
from dataclasses import dataclass, field

from app.llm.base import LLMProvider, Message, agent_tag, complete_with_json_retry, fill_template

logger = logging.getLogger(__name__)

INTENTS = ("none", "generate_course", "open_skill", "checkin", "plan", "briefing", "open_map")
MAX_TITLES = 80

SYSTEM_PROMPT = (
    agent_tag("front_desk")
    + """
You are the front desk of a learning game. Classify the user's chat message
(next message) into exactly one intent. You do not run anything yourself.

Intents:
- generate_course: the user wants to learn a new topic. args: {{"topic": "..."}}
- open_skill: the user wants to open or take on one of the existing nodes below.
  args: {{"skill": "<node title>"}}
- checkin: the user reports how their day or condition went (sleep, exercise, meals).
- plan: the user asks what to study today.
- briefing: the user asks for a status report.
- open_map: the user wants to see their life tree (the map).
- none: anything else, including small talk. Never start an audit from chat.

Existing nodes (newest course first):
<nodes>
{nodes}
</nodes>

Rules:
- "reply" is one short, friendly sentence in English saying what you will do.
- For none, "reply" answers or asks what the user wants to do.
- If a generate_course message names no topic, use none and ask for the topic.

Output only JSON:
{{"intent": "none", "args": {{}}, "reply": "..."}}
"""
)


class FrontDeskError(Exception):
    """The front desk's output is unusable."""


@dataclass
class FrontDeskResult:
    intent: str
    reply: str
    args: dict = field(default_factory=dict)


class FrontDesk:
    def __init__(self, provider: LLMProvider):
        self._provider = provider

    def route(self, message: str, node_titles: list[str]) -> FrontDeskResult:
        titles = "\n".join(f"- {t}" for t in node_titles[:MAX_TITLES]) or "(none)"
        messages: list[Message] = [
            {"role": "system", "content": fill_template(SYSTEM_PROMPT, nodes=titles)},
            {"role": "user", "content": message},
        ]
        logger.info("front_desk.route() calling provider=%s", self._provider.name)
        raw = complete_with_json_retry(self._provider, messages)
        try:
            data = json.loads(raw)
        except (json.JSONDecodeError, TypeError) as exc:
            raise FrontDeskError("front desk output is not JSON") from exc
        if not isinstance(data, dict):
            raise FrontDeskError("front desk output is not an object")
        reply = data.get("reply")
        if not isinstance(reply, str) or not reply.strip():
            raise FrontDeskError("front desk returned no reply")
        intent = data.get("intent")
        args = data.get("args")
        if not isinstance(args, dict):
            args = {}
        if intent not in INTENTS:
            # An intent we do not know cannot be run; keep the reply and run nothing.
            logger.warning("front desk returned an unknown intent %r, treating it as none", intent)
            intent, args = "none", {}
        return FrontDeskResult(intent=intent, reply=" ".join(reply.split()), args=args)
