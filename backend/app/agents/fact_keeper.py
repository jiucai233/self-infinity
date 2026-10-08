"""Fact Keeper (contract #40): keeps the short list of lasting facts about the player up to date
from what they say in check-ins and chat.

One call reads what was said next to the list and answers with changes, the operations of Mem0
[Chhikara et al., 2025]: add a new fact, update one that changed, end one that no longer holds;
most messages change nothing. Code applies them (app/services/facts.py): an update or an end
never deletes, it ends the old row, so the history stays, as in Zep's temporal graph
[Rasmussen et al., 2025]. The list is capped like MemGPT's core memory [Packer et al., 2023]: what
the Life Coach reads stays small however long the player has been talking.

Only what the player said, in their words: one day's sleep, mood or meals belong to the check-in,
and a condition they did not name is never inferred.
"""

import json
import logging
from dataclasses import dataclass
from datetime import date

from app.llm.base import LLMProvider, Message, agent_tag, complete_with_json_retry, fill_template
from app.models import FactCategory, LifeFact
from app.schemas import FACT_CHARS

logger = logging.getLogger(__name__)

OPS = ("add", "update", "end")

SYSTEM_PROMPT = (
    agent_tag("fact_keeper")
    + """
You keep a short list of lasting facts about a learner: things that will
still be true in a few weeks and matter for how they live or study.

Today: {today}
The list now ({count} of at most {max_facts}):
<facts>
{facts}
</facts>

What counts as lasting:
- health: an injury, illness or condition they name themselves, and what it
  rules out or how long it lasts
- schedule: a regular pattern (night shifts, classes on Mondays, a long
  commute) or a period with an end (exams until 15 Dec, travelling next week)
- constraint: something they cannot or must not do for a while
- preference: a stable way they like to live or study (vegetarian, studies
  best early in the morning)

Never keep:
- one day's things: last night's sleep, today's mood, a meal, today's
  workout. The daily check-in records those.
- a guess. Only what they said; never name a condition they did not name.
- anything about other people.

Changes:
- {{"op": "add", "category": "health", "text": "..."}}: a new lasting fact.
- {{"op": "update", "id": 3, "text": "..."}}: a fact on the list changed
  (the knee is better and short runs are fine again). The old one is kept as
  history, so the new text stands alone and still names what it is about
  ("Knee recovering; short easy runs only"). "category" may be given too.
- {{"op": "end", "id": 3}}: no longer true and nothing replaces it (the knee
  has healed).
Most messages change nothing: then answer {{"changes": []}}.
Do not add what the list already says. When the list is full, add only after
ending or updating one.

text: a short note, at most 80 characters, no subject ("Torn left knee
ligament; no running", "Night shifts, 22:00-06:00"). When they give a time
span, turn it into a date using today ("for six weeks" -> "until 19 Nov"),
so the note still reads right later.

Output only JSON: {{"changes": [...]}}
"""
)


class FactKeeperError(Exception):
    """The keeper's output is unusable."""


@dataclass
class Change:
    op: str  # "add" | "update" | "end"
    fact_id: int | None = None
    category: FactCategory | None = None
    text: str | None = None


def fact_line(fact: LifeFact) -> str:
    return f"[{fact.id}] {fact.category.value} · since {fact.created_at.date().isoformat()} · {fact.text}"


def _text(value: object) -> str | None:
    text = " ".join(str(value or "").split())[:FACT_CHARS].strip()
    return text or None


def _category(value: object) -> FactCategory | None:
    try:
        return FactCategory(str(value))
    except ValueError:
        return None


def parse_changes(data: object) -> list[Change]:
    """The well-formed changes; anything else is dropped."""
    items = data.get("changes") if isinstance(data, dict) else None
    if not isinstance(items, list):
        raise FactKeeperError('fact keeper output has no "changes" list')
    changes = []
    for item in items:
        if not isinstance(item, dict) or item.get("op") not in OPS:
            continue
        op = item["op"]
        fact_id = item.get("id")
        if op != "add" and not (isinstance(fact_id, int) and not isinstance(fact_id, bool)):
            continue
        text = _text(item.get("text"))
        if op != "end" and text is None:
            continue
        changes.append(Change(op=op, fact_id=fact_id if op != "add" else None, category=_category(item.get("category")), text=text))
    return changes


class FactKeeper:
    def __init__(self, provider: LLMProvider):
        self._provider = provider

    def changes(self, said: str, facts: list[LifeFact], today: date, max_facts: int) -> list[Change]:
        messages: list[Message] = [
            {
                "role": "system",
                "content": fill_template(
                    SYSTEM_PROMPT,
                    today=today.isoformat(),
                    count=str(len(facts)),
                    max_facts=str(max_facts),
                    facts="\n".join(fact_line(f) for f in facts) or "(empty)",
                ),
            },
            {"role": "user", "content": f"<said>\n{said}\n</said>"},
        ]
        logger.info("fact_keeper.changes() calling provider=%s facts=%d", self._provider.name, len(facts))
        try:
            data = json.loads(complete_with_json_retry(self._provider, messages))
        except (json.JSONDecodeError, TypeError) as exc:
            raise FactKeeperError("fact keeper output is not JSON") from exc
        return parse_changes(data)
