"""Life Coach (contract #39): three small pieces of advice on how the player lives, from their own
numbers.

It sees only coarse facts (app/services/life.py `coach_facts`): averages, counts, a weight change
and the player's own patterns with their day counts, next to their identity, win condition, rules,
main quests and the lasting facts they have told us (an injury, a work shift; contract #40).
Never a day's row or a meal. It coaches; it does not diagnose: no medical or
psychological judgement, no medication, no calorie counting or diet plans. Patterns are the
player's own few days, so it offers them as something to test, never as a cause.
"""

import json
import logging
from dataclasses import dataclass

from app.llm.base import LLMProvider, Message, agent_tag, complete_with_json_retry

logger = logging.getLogger(__name__)

ITEMS = 3
TITLE_CHARS = 40
BODY_CHARS = 280
BASED_ON_CHARS = 100

SYSTEM_PROMPT = (
    agent_tag("life_coach")
    + """
You are a lifestyle coach inside a learning game. The player logs sleep,
exercise, focus, stress and sometimes weight, and learns by explaining ideas
in audits. Give them exactly 3 pieces of advice for the coming week.

Facts about the player (JSON, their own numbers over the last
{window_days} days):
<facts>
{facts}
</facts>

Rules:
- Each piece rests on one fact above; "based_on" names it with its number
  ("slept 5.8 h on average", "passed 4 of 5 audits on days with 7 h+").
- "patterns" compare the player's own days in two groups, with day counts.
  They are few days and many things differ between them: offer a pattern as
  something to try and watch, never as a cause.
- "lasting" are things the player told us hold for a while (an injury, a
  work shift, exams). Never advise against them: no running on an injured
  knee, no early mornings for a night-shift worker. A piece may rest on one.
- Small and concrete: one thing they can do this week, tied to their win
  condition, rules or main quests when it fits.
- With few days logged, one piece may be about logging more days.
- Never diagnose, never name a medical or psychological condition, never
  suggest medication, calorie counts or a diet plan. If the numbers look
  worrying (for example very little sleep for many days), suggest talking to
  a professional.
- No praise, no reassurance, no exclamation marks.
- title: at most 40 characters. body: one or two sentences. Write in English.

Output only JSON:
{{"advice": [{{"title": "...", "body": "...", "based_on": "..."}}]}}
"""
)


class LifeCoachError(Exception):
    """The coach's output is unusable."""


@dataclass
class Advice:
    title: str
    body: str
    based_on: str


def _clip(value: object, limit: int) -> str:
    return " ".join(str(value or "").split())[:limit].strip()


class LifeCoach:
    def __init__(self, provider: LLMProvider):
        self._provider = provider

    def advise(self, facts: dict) -> list[Advice]:
        messages: list[Message] = [
            {
                "role": "system",
                "content": SYSTEM_PROMPT.format(
                    window_days=facts.get("window_days", 14),
                    facts=json.dumps(facts, ensure_ascii=False, indent=1),
                ),
            },
            {"role": "user", "content": "Give me this week's advice."},
        ]
        logger.info("life_coach.advise() calling provider=%s", self._provider.name)
        try:
            data = json.loads(complete_with_json_retry(self._provider, messages))
        except (json.JSONDecodeError, TypeError) as exc:
            raise LifeCoachError("life coach output is not JSON") from exc
        items = data.get("advice") if isinstance(data, dict) else None
        if not isinstance(items, list):
            raise LifeCoachError('life coach output has no "advice" list')
        advice = []
        for item in items:
            if not isinstance(item, dict):
                continue
            title, body = _clip(item.get("title"), TITLE_CHARS), _clip(item.get("body"), BODY_CHARS)
            if title and body:
                advice.append(Advice(title=title, body=body, based_on=_clip(item.get("based_on"), BASED_ON_CHARS)))
        if not advice:
            raise LifeCoachError("life coach gave no usable advice")
        return advice[:ITEMS]
