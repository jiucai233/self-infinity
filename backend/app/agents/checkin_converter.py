"""Check-in Converter (plan 7.4): a spoken daily check-in to the DailyCheckIn fields.

It records only what the user explicitly said; a field not mentioned stays null. Code
checks the output: out-of-range values become null, unknown keys are ignored. It never
raises: a failed conversion is all-null and the caller keeps the transcript.
"""

import json
import logging
from dataclasses import dataclass, fields
from datetime import date

from app.llm.base import LLMProvider, Message, agent_tag, complete_with_json_retry

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = (
    agent_tag("checkin_converter")
    + """
Convert the user's spoken daily check-in (next message) into fields.

Today's date: {date}

Fields:
- sleep_hours: hours slept last night, integer 0 to 14
- exercised: whether the user said they exercised in the last day, true or false
- diet_note: what the user said they ate, as a short phrase
- focus: self-rated focus, integer 1 to 5, only if the user said a number
- stress: self-rated stress, integer 1 to 5, only if the user said a number

Rules:
- Extract only what the user explicitly said. Never infer.
  "I'm a bit tired" says nothing about sleep hours, focus or stress.
- Any field that was not mentioned is null.
- Round approximate numbers: "about six hours" becomes 6.
- Write diet_note in English.

Output only JSON:
{{"sleep_hours": null, "exercised": null, "diet_note": null, "focus": null, "stress": null}}
"""
)


@dataclass
class ConvertedCheckin:
    sleep_hours: int | None = None
    exercised: bool | None = None
    diet_note: str | None = None
    focus: int | None = None
    stress: int | None = None

    def missing_fields(self) -> list[str]:
        return [f.name for f in fields(self) if getattr(self, f.name) is None]


def _int_in(value, low: int, high: int) -> int | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    number = round(value)
    return number if low <= number <= high else None


class CheckinConverter:
    def __init__(self, provider: LLMProvider):
        self._provider = provider

    def convert(self, transcript: str, today: date) -> ConvertedCheckin:
        messages: list[Message] = [
            {"role": "system", "content": SYSTEM_PROMPT.format(date=today.isoformat())},
            {"role": "user", "content": transcript},
        ]
        logger.info("checkin_converter.convert() calling provider=%s", self._provider.name)
        try:
            data = json.loads(complete_with_json_retry(self._provider, messages))
            if not isinstance(data, dict):
                raise ValueError("output is not a JSON object")
        except Exception:
            logger.warning("check-in converter failed, leaving every field empty", exc_info=True)
            return ConvertedCheckin()

        diet = data.get("diet_note")
        diet_note = " ".join(diet.split()) if isinstance(diet, str) else ""
        exercised = data.get("exercised")
        return ConvertedCheckin(
            sleep_hours=_int_in(data.get("sleep_hours"), 0, 14),
            exercised=exercised if isinstance(exercised, bool) else None,
            diet_note=diet_note or None,
            focus=_int_in(data.get("focus"), 1, 5),
            stress=_int_in(data.get("stress"), 1, 5),
        )
