"""Guide: the home chat's own voice for messages the front desk routes to `none` (small talk,
questions, follow-ups), and one line of feedback after a check-in is logged.

It gets what code already knows, computed without an LLM (app/services/chat.py `guide_context`):
the recent chat, older lines that share words with the message, today's check-in, the condition,
today's quests, the last audits, lessons, the lasting facts (contract #40) and the node titles.
It talks; it never runs anything (AD-7): no audit starts here, no action is claimed. When the
user wants an action the router missed, it says how to ask for it.

Calories only when the user asks how many calories something they ate has: a rough range from
what they logged or said, said to be rough. Never unprompted, no diet plans, no judgement of
food. (The Life Coach keeps its own no-calorie rule.)
"""

import json
import logging

from app.llm.base import LLMProvider, Message, agent_tag, complete_with_json_retry, fill_template

logger = logging.getLogger(__name__)

MAX_REPLY = 600
MAX_FEEDBACK = 300
TURN_CHARS = 400

# (speaker, text): "User", "Guide", "Check-in", ...
Turn = tuple[str, str]


def transcript(turns: list[Turn]) -> str:
    """Chat lines, oldest first, one per line, each cut to TURN_CHARS."""
    return "\n".join(f"{speaker}: {' '.join(text.split())[:TURN_CHARS]}" for speaker, text in turns) or "(none)"


CHAT_PROMPT = (
    agent_tag("guide")
    + """
Mode: chat
You are the Guide of a learning game: the player explains ideas in audits
to master nodes of their life tree, and logs their day (sleep, meals,
exercise, focus, stress) in check-ins. You answer their latest chat
message, which comes next.

The chat so far, oldest first:
<recent>
{recent}
</recent>

Older lines that may be related (from earlier days):
<older>
{older}
</older>

What the game knows about the player (JSON):
<context>
{context}
</context>

The front desk's draft reply (a classifier's one-line guess, without the
chat or the context):
<draft>
{draft}
</draft>

Rules:
- Write a better reply than the draft. Keep a question the draft asks when
  an action needs it (the topic of a new course, which node they mean).
- Read the message with the chat so far: "I told you", "the one I said"
  refer to earlier lines and to today's check-in. Do not ask again for
  what is already there.
- Use only what is above or in the message. Never invent numbers, audits,
  nodes or things the player did.
- You run nothing. Never say you started, logged, opened or planned
  anything. If they want an action, tell them in a few words how to ask
  (for example "say 'log my day: ...'", "ask 'what should I study today'",
  "open the node from the map"). Audits start only from a node.
- Calories: only when the player asks how many calories something they ate
  has, give a rough range in kcal from what they logged or said, say it is
  a rough estimate, and stop. Never bring up calories otherwise. No diet
  plans, no judging food.
- No medical or psychological diagnosis.
- Short: one to three sentences. Warm but plain: no flattery, no praise,
  at most one exclamation mark.
- Reply in the language of the player's latest message.

Output only JSON:
{{"reply": "..."}}
"""
)

FEEDBACK_PROMPT = (
    agent_tag("guide")
    + """
Mode: checkin_feedback
You are the Guide of a learning game. The player just logged today's
check-in. Say in one or two short sentences what it changes today, with
one concrete suggestion.

What the game knows (JSON; "checkin" is what was just logged):
<context>
{context}
</context>

How the game uses it:
- condition.flag "low" (average sleep under 6 h, stress 4+ or focus 2 or
  less over the last check-ins): audits keep their questions short and
  today's focus budget is smaller. "normal": audits as usual.

Rules:
- Ground it in the logged numbers (name one, e.g. "5 h of sleep").
- One concrete suggestion for today's learning (a lighter node, a review
  instead of a new node, a shorter session, an audit at their sharpest
  time). Nothing about calories or diet.
- No medical claims, no diagnosis, no praise, no exclamation marks.
- Write in the language of the player's check-in.

Output only JSON:
{{"reply": "..."}}
"""
)


class GuideError(Exception):
    """The Guide's output is unusable."""


def _reply(raw: str, limit: int) -> str:
    try:
        data = json.loads(raw)
    except (json.JSONDecodeError, TypeError) as exc:
        raise GuideError("guide output is not JSON") from exc
    reply = data.get("reply") if isinstance(data, dict) else None
    if not isinstance(reply, str) or not reply.strip():
        raise GuideError("guide returned no reply")
    return reply.strip()[:limit].strip()


def _json(value: dict) -> str:
    return json.dumps(value, ensure_ascii=False, indent=1, default=str)


class Guide:
    def __init__(self, provider: LLMProvider):
        self._provider = provider

    def reply(self, message: str, recent: list[Turn], older: list[Turn], context: dict, draft: str = "") -> str:
        messages: list[Message] = [
            {
                "role": "system",
                "content": fill_template(
                    CHAT_PROMPT,
                    recent=transcript(recent),
                    older=transcript(older),
                    context=_json(context),
                    draft=" ".join(draft.split()) or "(none)",
                ),
            },
            {"role": "user", "content": message},
        ]
        logger.info("guide.reply() calling provider=%s", self._provider.name)
        return _reply(complete_with_json_retry(self._provider, messages), MAX_REPLY)

    def checkin_feedback(self, said: str, context: dict) -> str:
        messages: list[Message] = [
            {"role": "system", "content": fill_template(FEEDBACK_PROMPT, context=_json(context))},
            {"role": "user", "content": said},
        ]
        logger.info("guide.checkin_feedback() calling provider=%s", self._provider.name)
        return _reply(complete_with_json_retry(self._provider, messages), MAX_FEEDBACK)
