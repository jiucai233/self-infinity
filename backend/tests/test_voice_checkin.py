"""A day's check-in said in pieces, by voice: the Guide's tool reads its summary and the user's
words, a later piece fills the day in instead of wiping it, and what the Guide only talked about
is logged by the backstop (contract #12, #36)."""

from datetime import date

import pytest
from sqlmodel import Session, select

from app.models import DailyCheckIn
from app.services import checkin
from tests.helpers import ScriptedProvider

TODAY = date(2026, 10, 8)


@pytest.fixture(autouse=True)
def fixed_today(monkeypatch):
    monkeypatch.setattr("app.services.checkin.local_today", lambda: TODAY)


def today(client) -> dict | None:
    return client.get("/api/checkins/today").json()


def act(client, said: str, summary: str = "") -> dict:
    return client.post("/api/chat/act", json={"intent": "checkin", "args": {"said": summary}, "said": said}).json()


def log(client, *user_lines: str) -> None:
    client.post(
        "/api/chat/log",
        json={"messages": [*({"role": "user", "content": u} for u in user_lines), {"role": "assistant", "content": "Okay."}]},
    )


def test_bed_and_wake_times_are_hours_slept(client):
    act(client, "I slept from 11 to 7.")
    assert today(client)["sleep_hours"] == 8


def test_the_guides_summary_carries_what_was_said_before_the_tool_call(client, monkeypatch):
    provider = ScriptedProvider()
    monkeypatch.setattr("app.routers.chat.get_provider", lambda agent=None: provider)

    act(client, said="And I ran for 20 minutes.", summary="I slept from 11 to 7. And I ran for 20 minutes.")

    (messages,) = provider.calls_for("checkin_converter")
    # The summary first, then the user's own last words; one copy of each.
    assert messages[-1]["content"] == "I slept from 11 to 7. And I ran for 20 minutes.\nAnd I ran for 20 minutes."
    assert (today(client)["sleep_hours"], today(client)["exercise_minutes"]) == (8, 20)


def test_a_later_piece_fills_the_day_in_instead_of_wiping_it(client):
    act(client, "I slept from 11 to 7.")
    act(client, "I ran for 20 minutes.")

    day = today(client)
    assert (day["sleep_hours"], day["exercise_minutes"], day["exercised"]) == (8, 20, True)
    assert day["transcript"] == "I slept from 11 to 7.\nI ran for 20 minutes."


def test_what_the_guide_only_talked_about_is_still_logged(client):
    log(client, "Morning! I slept from 11 to 7.")
    assert today(client)["sleep_hours"] == 8


def test_talk_that_reports_nothing_logs_no_day(client, client_engine):
    log(client, "What is a convolution, again?")

    assert today(client) is None
    with Session(client_engine) as session:
        assert session.exec(select(DailyCheckIn)).all() == []


def test_the_backstop_keeps_what_was_logged_before(client):
    client.post("/api/checkins", json={"sleep_hours": 8, "stress": 2})
    log(client, "I ran for 30 minutes after class.")

    day = today(client)
    assert (day["sleep_hours"], day["stress"], day["exercise_minutes"]) == (8, 2, 30)


# ---------------------------------------------------------------- the gate in front of the backstop


def gate(answer, confidence=0.9):
    def decide(input_text, questions):
        assert [q["name"] for q in questions] == ["daily"]
        return {"daily": (answer, confidence)}

    return decide


@pytest.fixture
def session(client_engine):
    with Session(client_engine) as s:
        yield s


def test_a_confident_no_skips_the_converter(session):
    provider = ScriptedProvider()
    assert checkin.record_said(session, "I slept 7 hours", provider, decide=gate("no")) is None
    assert provider.calls_for("checkin_converter") == []


@pytest.mark.parametrize("decide", [gate("yes"), gate("no", confidence=0.5), lambda *_: 1 / 0])
def test_yes_an_unsure_no_or_a_failing_gate_asks_the_converter(session, decide):
    record = checkin.record_said(session, "I slept 7 hours", ScriptedProvider(), decide=decide)
    assert record is not None and record.sleep_hours == 7
