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
- sleep_quality: self-rated sleep quality, integer 1 to 5, only if the user
  said a number for it
- exercise_minutes: how many minutes they exercised, integer, only if they
  said a duration ("ran for half an hour" is 30)
- weight_kg: their body weight in kilograms, only if they said it (convert
  pounds: 1 lb = 0.4536 kg), one decimal

Rules:
- Extract only what the user explicitly said. Never infer.
  "I'm a bit tired" says nothing about sleep hours, focus or stress.
- Any field that was not mentioned is null.
- Bed and wake times count as said: "slept from 11 to 7" is 8 hours,
  "went to bed at 12:30 and got up at 7" is 7 (rounded). Use the times they
  gave; never guess one they did not.
- Round approximate numbers: "about six hours" becomes 6.
- Write diet_note in English.

Output only JSON:
{{"sleep_hours": null, "exercised": null, "diet_note": null, "focus": null, "stress": null,
  "sleep_quality": null, "exercise_minutes": null, "weight_kg": null}}
"""
)


@dataclass
class ConvertedCheckin:
    sleep_hours: int | None = None
    exercised: bool | None = None
    diet_note: str | None = None
    focus: int | None = None
    stress: int | None = None
    # Never asked for: not part of missing_fields.
    sleep_quality: int | None = None
    exercise_minutes: int | None = None
    weight_kg: float | None = None

    def missing_fields(self) -> list[str]:
        return [f.name for f in fields(self)[:5] if getattr(self, f.name) is None]


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
        minutes = _int_in(data.get("exercise_minutes"), 0, 600)
        weight = data.get("weight_kg")
        weight_kg = round(float(weight), 1) if isinstance(weight, (int, float)) and not isinstance(weight, bool) else None
        return ConvertedCheckin(
            sleep_hours=_int_in(data.get("sleep_hours"), 0, 14),
            # Minutes of exercise say they exercised.
            exercised=exercised if isinstance(exercised, bool) else (True if minutes else None),
            diet_note=diet_note or None,
            focus=_int_in(data.get("focus"), 1, 5),
            stress=_int_in(data.get("stress"), 1, 5),
            sleep_quality=_int_in(data.get("sleep_quality"), 1, 5),
            exercise_minutes=minutes,
            weight_kg=weight_kg if weight_kg is not None and 20 <= weight_kg <= 400 else None,
        )
