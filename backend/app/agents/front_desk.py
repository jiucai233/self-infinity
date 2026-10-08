"""Front desk (contract section 5): classifies one chat message into an intent.

It only classifies and words a short reply. It never runs anything: code does that
(app/services/chat.py, AD-7). Output is parsed defensively; anything unusable raises
FrontDeskError, which the chat endpoint turns into a 502.

With a `decide` (the Decisions API, ~0.3 s) it first picks the intent and the node from fixed
choices. Intents that need no words of their own (check-in, plan, briefing, map, a named node)
answer from fixed texts right there. A new course (its topic must be read out of the message),
small talk (it needs a reply) and anything unsure go to the LLM as before.
"""

import json
import logging
from collections.abc import Callable
from dataclasses import dataclass, field

from app.i18n import quote, t
from app.llm.base import LLMProvider, Message, agent_tag, complete_with_json_retry, fill_template
from app.llm.decisions import choice

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


# The fast path: the intents' descriptions for the Decisions API, and the fixed reply of those
# it answers without the LLM.
INTENT_CHOICES = (
    ("generate_course", "Wants to learn a new topic that is not one of their nodes."),
    ("open_skill", "Wants to open, study or take on one of their existing nodes."),
    ("checkin", "Reports how their day or condition went: sleep, exercise, meals, focus, stress."),
    ("plan", "Asks what to study today or what to do next."),
    ("briefing", "Asks for a status report on their progress."),
    ("open_map", "Wants to see their life tree, the map of everything."),
    ("none", "Anything else: small talk, questions, unclear requests."),
)
FIXED_REPLIES = {"checkin": "logging_day", "plan": "picking_quests", "briefing": "status_coming", "open_map": "opening_map"}
NO_NODE = "(none)"
CONFIDENT = 0.75

Decide = Callable[[str, list[dict]], dict[str, tuple[str, float]]]


class FrontDeskError(Exception):
    """The front desk's output is unusable."""


@dataclass
class FrontDeskResult:
    intent: str
    reply: str
    args: dict = field(default_factory=dict)


class FrontDesk:
    def __init__(self, provider: LLMProvider, decide: Decide | None = None):
        self._provider = provider
        self._decide = decide

    def route(self, message: str, node_titles: list[str]) -> FrontDeskResult:
        node_titles = list(dict.fromkeys(node_titles[:MAX_TITLES]))
        if self._decide is not None:
            fast = self._route_fast(message, node_titles)
            if fast is not None:
                return fast
        return self._route_llm(message, node_titles)

    def _route_fast(self, message: str, node_titles: list[str]) -> FrontDeskResult | None:
        """The intent from fixed choices, or None when the LLM should answer instead."""
        questions = [choice(
            "intent", "The player sent this chat message to the front desk of a learning game. What do they want?",
            list(INTENT_CHOICES),
        )]
        if node_titles:
            questions.append(choice(
                "node", "Which of the player's nodes does the chat message name, if any?",
                [(title, "") for title in node_titles] + [(NO_NODE, "It names none of them.")],
            ))
        nodes = "\n".join(f"- {title}" for title in node_titles) or "(none)"
        try:
            answers = self._decide(f"Player's nodes:\n{nodes}\n\nChat message:\n{message}", questions)
            intent, confidence = answers["intent"]
        except Exception:
            logger.warning("front desk decisions failed, asking the LLM", exc_info=True)
            return None
        if confidence < CONFIDENT:
            return None
        if intent in FIXED_REPLIES:
            return FrontDeskResult(intent=intent, reply=t(FIXED_REPLIES[intent]))
        if intent == "open_skill":
            node, node_confidence = answers.get("node", (NO_NODE, 0.0))
            if node in node_titles and node_confidence >= CONFIDENT:
                return FrontDeskResult(intent=intent, reply=t("opening_node", title=quote(node)), args={"skill": node})
        return None

    def _route_llm(self, message: str, node_titles: list[str]) -> FrontDeskResult:
        titles = "\n".join(f"- {title}" for title in node_titles) or "(none)"
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
