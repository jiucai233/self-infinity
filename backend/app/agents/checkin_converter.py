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
- focus: self-rated focus, integer 1 to 5, from a number or a clear verbal description
- stress: self-rated stress, integer 1 to 5, from a number or a clear verbal description
- sleep_quality: self-rated sleep quality, integer 1 to 5, from a number or a clear
  verbal description of how well they slept
- exercise_minutes: how many minutes they exercised, integer, only if they
  said a duration ("ran for half an hour" is 30)
- weight_kg: their body weight in kilograms, only if they said it (convert
  pounds: 1 lb = 0.4536 kg), one decimal

{anchors}
- A number the user said always wins over any words.
- Only a clear description of that very state counts. If the words do not clearly
  speak to it, leave it null. Do not invent a value.
  "今天特别累，脑子转不动" gives focus 1 (the brain will not work) but says nothing
  about stress. "I'm a bit tired" says nothing about focus or stress.

Rules:
- Extract only what the user explicitly said. Never infer.
  "I'm a bit tired" says nothing about sleep hours, focus or stress.
  (A description of the state itself, see the verbal ratings above, is said.)
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

# Word-to-number anchors. Kept apart from SYSTEM_PROMPT because the prompt itself is
# English-only; the zh/ko words are the user-language examples the model matches against.
VERBAL_ANCHORS = """Verbal ratings (focus, stress, sleep_quality): when the user describes the state in
words instead of a number, map it to the 1 to 5 scale with these anchors, in any
language. Pick the nearest anchor.
- stress: 1 = none / 完全没压力 / 스트레스 전혀 없음 ("not stressed at all");
  2 = low / 压力不大 / 스트레스 별로 없어 ("pretty relaxed");
  3 = moderate / 一般 / 보통 ("some stress");
  4 = high / 压力有点大 / 스트레스 많아 ("quite stressed");
  5 = extreme / 非常大, 崩溃 / 스트레스 극심 ("overwhelmed")
- focus: 1 = terrible / 完全无法集中, 脑子转不动 / 집중 전혀 안 됨;
  2 = poor / 不太能集中 / 집중 잘 안 됨;
  3 = average / 一般 / 보통;
  4 = good / 比较专注 / 집중 잘 됨;
  5 = excellent / 非常专注, 状态极佳 / 집중 최고 ("locked in")
- sleep_quality: 1 = awful / 睡得很差 / 최악; 2 = poor / 睡得不好 / 별로;
  3 = okay / 一般 / 보통; 4 = good / 睡得不错 / 좋음; 5 = excellent / 睡得很好 / 아주 좋음
"""


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
            {"role": "system", "content": SYSTEM_PROMPT.format(date=today.isoformat(), anchors=VERBAL_ANCHORS)},
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
