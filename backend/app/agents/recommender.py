"""Recommender (plan 7.4): orders the nodes the user should study next.

It creates no node; it picks from the available ones. Code checks the output: every skill_id
must be in the input list, duplicates are dropped, at most 5 are kept. If nothing remains the
plan fails (the caller answers 502).
"""

import json
import logging
from dataclasses import dataclass, field

from app.llm.base import LLMProvider, Message, agent_tag, complete_with_json_retry, fill_template
from app.services.profile import MisconceptionCluster

logger = logging.getLogger(__name__)

MAX_STEPS = 5

SYSTEM_PROMPT = (
    agent_tag("recommender")
    + """
Choose what the user should study next.

Available nodes (JSON):
<available_nodes>
{available_nodes}
</available_nodes>
Suggested difficulty tier: {suggested_tier}
Recurring misconceptions (JSON):
<clusters>
{clusters}
</clusters>
Condition: {condition_flag}   (normal | low | unknown)

Rules:
- Choose 3 to 5 nodes, in the order they should be studied.
- Use only skill_id values from the list.
- Rank nodes with no unmet requires before nodes with unmet requires.
- Prefer nodes where a recurring misconception is likely to come up again,
  so it can be tested.
- Prefer the suggested tier.
- If the condition is low, prefer leaf nodes (smaller units).
- rationale: one sentence on why this node now, based only on the inputs.
- focus_hint: one concrete thing to pay attention to while explaining it.
- Write rationale and focus_hint in English.

Output only JSON:
{{"steps": [{{"skill_id": 0, "rationale": "...", "focus_hint": "..."}}]}}
"""
)


class RecommenderError(Exception):
    """The Recommender's output is unusable, or no valid step remains after the checks."""


@dataclass
class Candidate:
    skill_id: int
    title: str
    position: str  # root | branch | leaf
    tier: str  # easy | medium | hard
    unmet_requires: list[str] = field(default_factory=list)


@dataclass
class PlanStep:
    skill_id: int
    rationale: str
    focus_hint: str


class Recommender:
    def __init__(self, provider: LLMProvider):
        self._provider = provider

    def recommend(
        self,
        candidates: list[Candidate],
        suggested_tier: str,
        clusters: list[MisconceptionCluster] | list,
        condition_flag: str,
    ) -> list[PlanStep]:
        nodes = [
            {
                "skill_id": c.skill_id,
                "title": c.title,
                "position": c.position,
                "tier": c.tier,
                "unmet_requires": c.unmet_requires,
            }
            for c in candidates
        ]
        cluster_data = [{"label": c.label, "skills": c.skills} for c in clusters]
        system = fill_template(
            SYSTEM_PROMPT,
            suggested_tier=suggested_tier,
            condition_flag=condition_flag,
            available_nodes=json.dumps(nodes, ensure_ascii=False, indent=1),
            clusters=json.dumps(cluster_data, ensure_ascii=False, indent=1),
        )
        messages: list[Message] = [
            {"role": "system", "content": system},
            {"role": "user", "content": "Write the study plan."},
        ]
        logger.info("recommender.recommend() calling provider=%s nodes=%d", self._provider.name, len(nodes))
        raw = complete_with_json_retry(self._provider, messages)
        return self._check(raw, {c.skill_id for c in candidates})

    @staticmethod
    def _check(raw: str, valid_ids: set[int]) -> list[PlanStep]:
        try:
            items = json.loads(raw)["steps"]
            if not isinstance(items, list):
                raise TypeError("steps is not a list")
        except (json.JSONDecodeError, KeyError, TypeError) as exc:
            raise RecommenderError("recommender output is not usable") from exc

        steps: list[PlanStep] = []
        seen: set[int] = set()
        for item in items:
            try:
                skill_id = item["skill_id"]
                if isinstance(skill_id, bool) or not isinstance(skill_id, (int, float, str)):
                    continue
                skill_id = int(skill_id)
            except (KeyError, TypeError, ValueError):
                continue
            if skill_id not in valid_ids or skill_id in seen:
                logger.warning("recommender gave an unknown or duplicate skill_id=%s, dropped", skill_id)
                continue
            seen.add(skill_id)
            steps.append(
                PlanStep(
                    skill_id=skill_id,
                    rationale=str(item.get("rationale") or "").strip(),
                    focus_hint=str(item.get("focus_hint") or "").strip(),
                )
            )
        if not steps:
            raise RecommenderError("no valid step left")
        return steps[:MAX_STEPS]
