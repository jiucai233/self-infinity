"""Check-in Converter agent (UT-22, UT-23) and POST /api/checkins (IT-24, IT-25)."""

import json
from datetime import date

import pytest
from sqlmodel import Session, select

from app.agents.checkin_converter import CheckinConverter
from app.llm.mock import MockProvider
from app.models import DailyCheckIn
from app.utils import local_today
from tests.helpers import BrokenProvider, CountingProvider, ScriptedProvider

TODAY = date(2026, 10, 5)
EXAMPLE = "I slept about six hours last night and didn't exercise. I had ramen for lunch and I'm a bit tired."


def convert(text: str, provider=None):
    return CheckinConverter(provider or MockProvider()).convert(text, TODAY)


def reply(**fields):
    base = {"sleep_hours": None, "exercised": None, "diet_note": None, "focus": None, "stress": None}
    return ScriptedProvider(checkin_converter=json.dumps({**base, **fields}, ensure_ascii=False))


def test_ut22_sleep_and_diet_filled_focus_and_stress_missing():
    result = convert(EXAMPLE)

    assert (result.sleep_hours, result.exercised, result.diet_note) == (6, False, "lunch: ramen")
    assert (result.focus, result.stress) == (None, None)
    assert result.missing_fields() == ["focus", "stress"]


def test_ut23_out_of_range_values_become_null():
    result = convert("x", reply(sleep_hours=20, focus=9, stress=0, exercised=True))

    assert (result.sleep_hours, result.focus, result.stress, result.exercised) == (None, None, None, True)


def test_unknown_keys_are_ignored_and_bad_types_become_null():
    result = convert("x", reply(sleep_hours="six", exercised="yes", diet_note=5, mood="good"))

    assert result.missing_fields() == ["sleep_hours", "exercised", "diet_note", "focus", "stress"]


def test_a_failing_or_garbled_provider_gives_all_null():
    assert convert("x", BrokenProvider()).missing_fields() == [
        "sleep_hours", "exercised", "diet_note", "focus", "stress"
    ]
    assert convert("x", ScriptedProvider(checkin_converter="not json")).sleep_hours is None


def test_the_prompt_carries_the_date_and_the_transcript_is_the_user_message():
    provider = reply()
    convert(EXAMPLE, provider)

    (messages,) = provider.calls_for("checkin_converter")
    assert messages[0]["content"].startswith("[agent: checkin_converter]")
    assert "2026-10-05" in messages[0]["content"]
    assert messages[1] == {"role": "user", "content": EXAMPLE}


# ---------------------------------------------------------------- the Mock script, contract 4.5


@pytest.mark.parametrize(
    "text, hours",
    [
        ("I slept 7 hours", 7),
        ("slept about six hours last night", 6),
        ("Slept for twelve hours", 12),
        ("I got 5.5 hours of sleep", 6),
        ("sleep: 8h", 8),
        ("I slept 6 hrs", 6),
        ("I slept badly", None),
        ("I worked 7 hours", None),  # no sleep word in that sentence
        ("I slept 20 hours", None),  # out of range
        ("7 hours of sleep. Then ate lunch.", 7),
    ],
)
def test_45_sleep_hours(text, hours):
    assert convert(text).sleep_hours == hours


@pytest.mark.parametrize(
    "text, exercised",
    [
        ("I didn't exercise", False),
        ("I didn’t exercise today", False),
        ("no exercise today", False),
        ("I skipped the gym", False),
        ("skipped gym", False),
        ("I didn't work out", False),
        ("I exercised this morning", True),
        ("I worked out", True),
        ("I went to the gym", True),
        ("I went for a run", True),
        ("I'm just tired", None),
    ],
)
def test_45_exercised(text, exercised):
    assert convert(text).exercised is exercised


@pytest.mark.parametrize(
    "text, note",
    [
        ("I had ramen for lunch", "lunch: ramen"),
        ("Had ramen and kimchi for Lunch", "lunch: ramen and kimchi"),
        ("I ate toast for breakfast", "breakfast: toast"),
        ("for dinner I had kimbap", "dinner: kimbap"),
        ("I had a long day and ate pizza for dinner.", "dinner: pizza"),
        ("I skipped lunch", None),
        ("I ate something", None),
    ],
)
def test_45_diet_note(text, note):
    assert convert(text).diet_note == note


@pytest.mark.parametrize(
    "text, focus, stress",
    [
        ("I focused well", 4, None),
        ("I couldn't focus", 2, None),
        ("I couldn’t focus at all", 2, None),
        ("I was stressed", None, 4),
        ("a lot of stress today", None, 4),
        ("I felt relaxed", None, 2),
        ("no stress", None, 2),
        ("I'm a bit tired", None, None),
    ],
)
def test_45_focus_and_stress(text, focus, stress):
    result = convert(text)

    assert (result.focus, result.stress) == (focus, stress)


def test_45_tired_infers_nothing():
    result = convert("I'm so tired today")

    assert result.missing_fields() == ["sleep_hours", "exercised", "diet_note", "focus", "stress"]


def test_45_a_whole_english_check_in_in_one_go():
    result = convert("I slept seven hours. I went to the gym. I had rice for dinner. I focused well but I was stressed.")

    assert (result.sleep_hours, result.exercised, result.diet_note, result.focus, result.stress) == (
        7, True, "dinner: rice", 4, 4,
    )


@pytest.mark.parametrize(
    "text, expected",
    [
        ("7시간 잤어요", {"sleep_hours": 7}),
        ("한 여섯 시간 잤고", {"sleep_hours": 6}),
        ("운동은 안 했어요", {"exercised": False}),
        ("점심은 라면 먹었고", {"diet_note": "점심 라면"}),
        ("집중이 안 돼요", {"focus": 2}),
        ("스트레스 많아요", {"stress": 4}),
    ],
)
def test_45_korean_rules_stay_as_a_fallback(text, expected):
    result = convert(text)

    for field, value in expected.items():
        assert getattr(result, field) == value


# ---------------------------------------------------------------- endpoint


def test_it24_voice_check_in_returns_fields_transcript_and_missing(client):
    response = client.post("/api/checkins", json={"transcript": EXAMPLE})

    assert response.status_code == 200
    assert response.json() == {
        "checkin": {
            "date": local_today().isoformat(),
            "sleep_hours": 6,
            "exercised": False,
            "diet_note": "lunch: ramen",
            "focus": None,
            "stress": None,
            "transcript": EXAMPLE,
            "source": "voice",
            "sleep_quality": None,
            "exercise_minutes": None,
            "weight_kg": None,
        },
        "missing_fields": ["focus", "stress"],
    }


def test_it24_the_follow_up_answer_completes_the_record(client):
    client.post("/api/checkins", json={"transcript": EXAMPLE})

    response = client.post("/api/checkins", json={"transcript": EXAMPLE + "\nI focused well but I was stressed."})

    body = response.json()
    assert (body["checkin"]["focus"], body["checkin"]["stress"], body["missing_fields"]) == (4, 4, [])


def test_it25_a_second_check_in_the_same_day_replaces_the_record(client, client_engine):
    client.post("/api/checkins", json={"transcript": EXAMPLE})

    response = client.post("/api/checkins", json={"sleep_hours": 8, "stress": 2})

    body = response.json()
    assert body["checkin"]["source"] == "manual"
    assert body["checkin"]["transcript"] is None
    # nothing is carried over from the first record
    assert (body["checkin"]["exercised"], body["checkin"]["diet_note"]) == (None, None)
    assert body["missing_fields"] == ["exercised", "diet_note", "focus"]
    with Session(client_engine) as session:
        rows = session.exec(select(DailyCheckIn)).all()
    assert len(rows) == 1 and rows[0].sleep_hours == 8


def test_manual_check_in_never_calls_the_llm(client, monkeypatch):
    provider = CountingProvider()
    monkeypatch.setattr("app.routers.checkins.get_provider", lambda agent=None: provider)

    response = client.post("/api/checkins", json={"sleep_hours": 6, "exercised": False, "diet_note": " lunch: ramen ", "focus": 3, "stress": 2})

    assert provider.counts == {}
    body = response.json()
    assert body["missing_fields"] == []
    assert body["checkin"]["diet_note"] == "lunch: ramen"


def test_a_transcript_wins_over_structured_fields(client):
    response = client.post("/api/checkins", json={"transcript": "I slept 7 hours", "sleep_hours": 3, "focus": 5})

    checkin = response.json()["checkin"]
    assert (checkin["source"], checkin["sleep_hours"], checkin["focus"]) == ("voice", 7, None)


def test_converter_failure_is_not_an_error(client, monkeypatch):
    monkeypatch.setattr("app.routers.checkins.get_provider", lambda agent=None: BrokenProvider())

    response = client.post("/api/checkins", json={"transcript": EXAMPLE})

    assert response.status_code == 200
    body = response.json()
    assert body["checkin"]["transcript"] == EXAMPLE
    assert body["missing_fields"] == ["sleep_hours", "exercised", "diet_note", "focus", "stress"]


@pytest.mark.parametrize(
    "body",
    [{}, {"transcript": "  "}, {"sleep_hours": 15}, {"sleep_hours": -1}, {"focus": 0}, {"focus": 6}, {"stress": 6},
     {"sleep_hours": None}, {"transcript": None}, {"exercised": "maybe"}],
)
def test_invalid_check_ins_are_422(client, body):
    assert client.post("/api/checkins", json=body).status_code == 422
