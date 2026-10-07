"""Course Scout: reads what a new player typed as their first course, with their main quest and
profile beside it, before anything is built.

A clear answer comes back as a tidy course title. A vague one ("idk, a lot of things") comes
back as three concrete first courses drawn from the player's own main quest and win condition,
for them to pick from. Never raises: a scout that fails means "build what they typed".
"""

import json
import logging
from dataclasses import dataclass, field

from app.llm.base import LLMProvider, Message, agent_tag, complete_with_json_retry

logger = logging.getLogger(__name__)

MAX_OPTIONS = 3
TITLE_CHARS = 80

SYSTEM_PROMPT = (
    agent_tag("course_scout")
    + """
You help a new player pick their first course in a learning game. Each course
becomes a tree of ideas they will have to explain. They were asked "What do you
want to learn first?". The next message has their main quest, their profile and,
last, their answer.

Decide one of two things:
- "clear": the answer names something learnable (a subject, a skill, a tool, a
  course, an exam, a project's know-how). Return it as a short course title:
  fix typos and expand shorthand only as far as needed ("so arm 101" ->
  "SO-ARM101 robot arm"). Keep what they asked for; do not widen or narrow it.
- "choose": the answer is not a topic, or too vague or too broad for one tree
  ("idk", "a lot of things", "everything", "something useful"). Offer exactly 3
  concrete first courses that would move their main quest or win condition
  forward, each with one short line on why. With no quest or profile, offer
  3 broadly useful starting courses.

Rules:
- Titles: at most 60 characters, a course name, not a sentence.
- Use only what the player wrote; do not invent facts about them.
- Write in English.

Output only JSON, one of:
{"kind": "clear", "topic": "..."}
{"kind": "choose", "question": "...", "options": [{"topic": "...", "why": "..."}]}
"""
)


@dataclass
class ScoutOption:
    topic: str
    why: str


@dataclass
class ScoutResult:
    kind: str  # "clear" or "choose"
    topic: str = ""
    question: str = ""
    options: list[ScoutOption] = field(default_factory=list)


@dataclass
class PlayerContext:
    """What the tutorial has asked before the course step."""

    main_quests: list[str] = field(default_factory=list)
    win_condition: str = ""
    stakes: str = ""
    identity: str = ""


def _brief(answer: str, context: PlayerContext) -> str:
    lines = [
        f"Main quest: {'; '.join(context.main_quests) or '(none)'}",
        f"Win condition: {context.win_condition or '(none)'}",
        f"Stakes: {context.stakes or '(none)'}",
        f"Identity: {context.identity or '(none)'}",
        f"Answer: {answer}",
    ]
    return "\n".join(lines)


def _title(value: object) -> str:
    return " ".join(str(value or "").split())[:TITLE_CHARS].strip()


class CourseScout:
    def __init__(self, provider: LLMProvider):
        self._provider = provider

    def scout(self, answer: str, context: PlayerContext) -> ScoutResult:
        answer = answer.strip()
        fallback = ScoutResult(kind="clear", topic=answer)
        messages: list[Message] = [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": _brief(answer, context)},
        ]
        logger.info("course_scout.scout() calling provider=%s", self._provider.name)
        try:
            data = json.loads(complete_with_json_retry(self._provider, messages))
            if data.get("kind") == "choose":
                options = []
                for raw in data.get("options") or []:
                    if not isinstance(raw, dict):
                        continue
                    topic = _title(raw.get("topic"))
                    if topic and topic.casefold() not in {o.topic.casefold() for o in options}:
                        options.append(ScoutOption(topic=topic, why=" ".join(str(raw.get("why") or "").split())))
                if options:
                    return ScoutResult(
                        kind="choose",
                        question=" ".join(str(data.get("question") or "").split()),
                        options=options[:MAX_OPTIONS],
                    )
            topic = _title(data.get("topic"))
            if data.get("kind") == "clear" and topic:
                return ScoutResult(kind="clear", topic=topic)
        except Exception:
            # Reading the answer must never block the build: fall back to what they typed.
            logger.warning("course scout failed, building what the player typed", exc_info=True)
        return fallback
