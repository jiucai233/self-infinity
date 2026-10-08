"""The life overview, editing a day's check-in, and the Life Coach (contract #39)."""

import json
from datetime import date, datetime, timedelta, timezone

import pytest
from sqlmodel import Session, select

from app.agents.checkin_converter import CheckinConverter
from app.llm.mock import MockProvider
from app.models import AuditSession, AuditStatus, DailyCheckIn, LifeAdvice
from app.services import life
from app.services.condition import current_condition
from tests.helpers import BrokenProvider, ScriptedProvider, generate, ids_by_slug, make_course, make_skill

TODAY = date(2026, 10, 8)


@pytest.fixture(autouse=True)
def fixed_today(monkeypatch):
    monkeypatch.setattr("app.services.life.local_today", lambda: TODAY)
    monkeypatch.setattr("app.services.checkin.local_today", lambda: TODAY)


def add_day(session, days_ago, **fields):
    session.add(DailyCheckIn(date=TODAY - timedelta(days=days_ago), **fields))
    session.commit()


def add_audit(session, skill, days_ago, passed):
    # 03:00 UTC is noon in Seoul: the same calendar day.
    when = datetime.combine(TODAY - timedelta(days=days_ago), datetime.min.time(), tzinfo=timezone.utc) + timedelta(hours=3)
    session.add(AuditSession(skill_id=skill.id, status=AuditStatus.passed if passed else AuditStatus.failed, created_at=when))
    session.commit()


# ---------------------------------------------------------------- GET /api/life


def test_an_empty_life_is_every_day_of_the_window_with_nothing_in_it(client):
    body = client.get("/api/life").json()

    assert len(body["days"]) == 30
    assert body["days"][0]["date"] == "2026-09-09" and body["days"][-1]["date"] == "2026-10-08"
    assert not any(d["checked_in"] for d in body["days"])
    assert body["summary"]["days_logged"] == 0 and body["summary"]["avg_sleep_hours"] is None
    assert body["patterns"] == [] and body["pattern_min_days"] == 5 and body["advice"] is None


def test_days_carry_their_check_in_and_their_audits(client, client_engine):
    with Session(client_engine) as session:
        skill = make_skill(session, make_course(session), "s")
        add_day(session, 0, sleep_hours=7, sleep_quality=4, exercise_minutes=30, weight_kg=71.5, focus=4, stress=2)
        add_day(session, 1, sleep_hours=5, exercised=False, weight_kg=72.0)
        add_audit(session, skill, 0, True)
        add_audit(session, skill, 0, False)
        session.add(AuditSession(skill_id=skill.id, status=AuditStatus.active))  # unfinished: not counted
        session.commit()

    body = client.get("/api/life", params={"days": 7}).json()

    today, yesterday = body["days"][-1], body["days"][-2]
    assert len(body["days"]) == 7
    assert today == {
        "date": "2026-10-08", "checked_in": True, "sleep_hours": 7, "sleep_quality": 4, "exercised": True,
        "exercise_minutes": 30, "weight_kg": 71.5, "diet_note": None, "focus": 4, "stress": 2, "audits": 2, "passed": 1,
    }
    assert (yesterday["exercised"], yesterday["audits"]) == (False, 0)
    s = body["summary"]
    assert (s["days"], s["days_logged"], s["avg_sleep_hours"], s["exercise_days"]) == (7, 2, 6.0, 1)
    assert (s["weight_first"], s["weight_last"], s["audits"], s["passed"]) == (72.0, 71.5, 2, 1)


def test_the_window_is_7_to_365_days(client):
    assert client.get("/api/life", params={"days": 6}).status_code == 422
    assert client.get("/api/life", params={"days": 366}).status_code == 422
    assert len(client.get("/api/life", params={"days": 365}).json()["days"]) == 365


def test_a_pattern_shows_once_each_group_has_five_days(client, client_engine):
    with Session(client_engine) as session:
        skill = make_skill(session, make_course(session), "s")
        for i in range(5):
            add_day(session, i, sleep_hours=8, focus=4)
            add_audit(session, skill, i, True)
        for i in range(5, 9):
            add_day(session, i, sleep_hours=5, focus=2)
            add_audit(session, skill, i, False)

    assert client.get("/api/life").json()["patterns"] == []

    with Session(client_engine) as session:
        add_day(session, 9, sleep_hours=4)
    (pattern,) = client.get("/api/life").json()["patterns"]

    assert pattern == {
        "kind": "sleep",
        "better": {"days": 5, "audits": 5, "pass_rate": 1.0, "avg_focus": 4.0},
        "worse": {"days": 5, "audits": 4, "pass_rate": 0.0, "avg_focus": 2.0},
    }


def test_patterns_count_the_whole_history_not_just_the_window(client, client_engine):
    with Session(client_engine) as session:
        for i in range(5):
            add_day(session, 100 + i, exercised=True)
            add_day(session, 200 + i, exercised=False)

    (pattern,) = client.get("/api/life", params={"days": 7}).json()["patterns"]
    assert pattern["kind"] == "exercise" and pattern["better"]["audits"] == 0 and pattern["better"]["pass_rate"] is None


# ---------------------------------------------------------------- PUT /api/checkins/{date}


def test_editing_a_day_sets_only_the_fields_sent(client):
    client.post("/api/checkins", json={"sleep_hours": 6, "focus": 3})

    body = client.put("/api/checkins/2026-10-08", json={"weight_kg": 70.2, "focus": None}).json()

    assert (body["sleep_hours"], body["focus"], body["weight_kg"]) == (6, None, 70.2)


def test_a_missed_day_can_be_filled_in_but_not_a_future_one(client):
    body = client.put("/api/checkins/2026-10-01", json={"exercise_minutes": 45}).json()

    assert (body["date"], body["exercise_minutes"], body["exercised"], body["source"]) == ("2026-10-01", 45, True, "manual")
    assert client.put("/api/checkins/2026-10-09", json={"focus": 3}).status_code == 400
    assert client.put("/api/checkins/2026-10-01", json={"weight_kg": 10}).status_code == 422


def test_the_new_fields_can_be_sent_with_a_manual_check_in(client):
    body = client.post("/api/checkins", json={"sleep_quality": 2, "weight_kg": 80}).json()

    assert (body["checkin"]["sleep_quality"], body["checkin"]["weight_kg"]) == (2, 80.0)
    # Never asked for: the follow-up still names only the five.
    assert body["missing_fields"] == ["sleep_hours", "exercised", "diet_note", "focus", "stress"]


# ---------------------------------------------------------------- the converter's new fields


def test_the_converter_reads_weight_minutes_and_sleep_quality_only_when_said():
    convert = CheckinConverter(MockProvider()).convert
    said = convert("I ran for 30 minutes and I weigh 72.5 kg. Sleep quality was 4.", TODAY)

    assert (said.exercise_minutes, said.exercised, said.weight_kg, said.sleep_quality) == (30, True, 72.5, 4)
    assert said.missing_fields() == ["sleep_hours", "diet_note", "focus", "stress"]
    quiet = convert("I slept about six hours.", TODAY)
    assert (quiet.exercise_minutes, quiet.weight_kg, quiet.sleep_quality) == (None, None, None)


def test_the_converter_drops_impossible_values():
    raw = json.dumps({"exercise_minutes": 9000, "weight_kg": 5, "sleep_quality": 9})
    converted = CheckinConverter(ScriptedProvider(checkin_converter=raw)).convert("x", TODAY)

    assert (converted.exercise_minutes, converted.weight_kg, converted.sleep_quality) == (None, None, None)


# ---------------------------------------------------------------- focus in the condition


def test_low_focus_makes_the_condition_low(client_engine):
    with Session(client_engine) as session:
        add_day(session, 0, sleep_hours=8, stress=2, focus=2)
        assert current_condition(session).flag == "low"


# ---------------------------------------------------------------- POST /api/life/advice


def test_advice_is_three_pieces_saved_and_read_back(client, client_engine):
    with Session(client_engine) as session:
        add_day(session, 0, sleep_hours=6, focus=3)

    advice = client.post("/api/life/advice").json()

    assert [a["title"] for a in advice["items"]] == ["Protect your sleep", "Audit when you focus best", "Log a few more days"]
    assert advice["items"][0]["based_on"] == "slept 6.0 h on average"
    assert client.get("/api/life").json()["advice"] == advice


def test_the_coach_sees_summaries_never_a_days_row(client, client_engine, monkeypatch):
    provider = ScriptedProvider()
    monkeypatch.setattr("app.routers.life.get_provider", lambda agent=None: provider)
    client.put("/api/profile", json={"identity": "I build robots", "rules": ["Sleep by 1"]})
    client.post("/api/goals", json={"title": "Ship the arm"})
    with Session(client_engine) as session:
        add_day(session, 0, sleep_hours=6, diet_note="ramen at 2am", weight_kg=70.0)
        add_day(session, 3, weight_kg=71.0)

    client.post("/api/life/advice")

    (system,) = provider.system_prompts("life_coach")
    facts = json.loads(system.split("<facts>\n")[1].split("\n</facts>")[0])
    assert "ramen" not in system and "2026-10-08" not in system
    assert facts["weight_change_kg"] == -1.0 and facts["days_logged"] == 2 and facts["window_days"] == 14
    assert facts["player"]["identity"] == "I build robots" and facts["player"]["main_quests"] == ["Ship the arm"]
    assert "Never diagnose" in system
    with Session(client_engine) as session:
        (row,) = session.exec(select(LifeAdvice)).all()
        assert json.loads(row.facts_json) == facts


@pytest.mark.parametrize("provider", [BrokenProvider(), ScriptedProvider(life_coach='{"advice": []}')])
def test_a_failing_coach_is_a_502_and_saves_nothing(client, client_engine, monkeypatch, provider):
    monkeypatch.setattr("app.routers.life.get_provider", lambda agent=None: provider)

    response = client.post("/api/life/advice")

    assert response.status_code == 502
    assert client.get("/api/life").json()["advice"] is None


def test_advice_never_has_more_than_three_pieces_and_cuts_long_text():
    from app.agents.life_coach import LifeCoach

    items = [{"title": "T" * 90, "body": "B" * 500, "based_on": "x"}] * 5
    advice = LifeCoach(ScriptedProvider(life_coach=json.dumps({"advice": items}))).advise({"window_days": 14})

    assert len(advice) == 3 and len(advice[0].title) == 40 and len(advice[0].body) == 280


def test_mastered_nodes_of_a_deleted_course_are_not_counted(client, monkeypatch):
    from tests.helpers import pass_node

    ids = ids_by_slug(generate(client, "Math"))
    pass_node(client, ids["discriminant"])
    client.delete("/api/courses/1")
    provider = ScriptedProvider()
    monkeypatch.setattr("app.routers.life.get_provider", lambda agent=None: provider)

    client.post("/api/life/advice")

    facts = json.loads(provider.system_prompts("life_coach")[0].split("<facts>\n")[1].split("\n</facts>")[0])
    assert facts["learning"]["nodes_mastered_total"] == 0
