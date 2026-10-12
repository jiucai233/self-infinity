"""The day's plan (app/services/day_plan.py, contract #15): the focus left by the condition, the
time of day deciding between judgement and review, reviews spaced out, and the player's own
numbers in the line above the quests."""

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import pytest
from sqlmodel import Session, select

from app.models import AuditSession, AuditTurn, DailyCheckIn
from app.services import day_plan
from tests.helpers import FIRST, LONG, SHORT, answer_turns, freeze_clock, generate, ids_by_slug, pass_node, start

KST = ZoneInfo("Asia/Seoul")


def at(when: str) -> datetime:
    return datetime.fromisoformat(when).replace(tzinfo=KST)


def move_audits(engine, skill_id: int, when: str, minutes: float = 5) -> None:
    """Every audit of the node started at `when` and had its last turn `minutes` later."""
    begin = at(when)
    with Session(engine) as session:
        for audit in session.exec(select(AuditSession).where(AuditSession.skill_id == skill_id)).all():
            audit.created_at = begin
            turns = session.exec(select(AuditTurn).where(AuditTurn.session_id == audit.id)).all()
            for i, turn in enumerate(turns):
                turn.created_at = begin + timedelta(minutes=minutes if i == len(turns) - 1 else 0)
                session.add(turn)
            session.add(audit)
        session.commit()


def checkin(client, **fields):
    return client.post("/api/checkins", json=fields)


def plan(client) -> dict:
    response = client.post("/api/plan/generate")
    assert response.status_code == 200, response.text
    return response.json()


def kinds(body) -> list[str]:
    return [s["kind"] for s in body["steps"]]


# ---------------------------------------------------------------- the pieces


@pytest.mark.parametrize(
    ("hour", "slot"),
    [(5, "morning"), (11, "morning"), (12, "afternoon"), (17, "afternoon"), (18, "evening"), (22, "evening"),
     (23, "night"), (0, "night"), (4, "night")],
)
def test_the_time_of_day(hour, slot):
    assert day_plan.slot_of(at(f"2026-10-05 {hour:02d}:30")) == slot


def test_the_focus_budget_follows_the_condition():
    assert [day_plan.focus_budget(f) for f in ("normal", "unknown", "low")] == [240, 180, 120]


def test_focus_spent_is_what_todays_audits_took(client, client_engine, monkeypatch):
    freeze_clock(monkeypatch, "2026-10-05 15:00")
    ids = ids_by_slug(generate(client))
    pass_node(client, ids["discriminant"])
    pass_node(client, ids["linear-function"])
    move_audits(client_engine, ids["discriminant"], "2026-10-05 09:00", minutes=20)
    move_audits(client_engine, ids["linear-function"], "2026-10-04 09:00", minutes=30)  # yesterday

    with Session(client_engine) as session:
        assert day_plan.focus_spent(session, at("2026-10-05 15:00")) == 20


# ---------------------------------------------------------------- plans by the time of day


def test_a_morning_plan_is_judgement_and_may_hold_a_challenge(client, monkeypatch):
    freeze_clock(monkeypatch, "2026-10-05 09:00")
    checkin(client, sleep_hours=8, stress=2, focus=4)
    generate(client, "Computer Vision", search_syllabus=False)

    body = plan(client)

    assert (body["slot"], body["condition_flag"], body["focus_budget"], body["focus_left"]) == ("morning", "normal", 240, 240)
    steps = {s["skill_title"]: s for s in body["steps"]}
    assert steps["Harris Corners"]["kind"] == "learn" and steps["Harris Corners"]["minutes"] == 25
    # Geometric Vision is a category not broken down: in the morning it can be taken on whole.
    assert steps["Geometric Vision"]["kind"] == "challenge" and steps["Geometric Vision"]["minutes"] == 35
    assert body["summary"].startswith("Morning: judgement first")
    assert "About 4 h of focus left today (0 min done)." in body["summary"]


def test_an_evening_plan_is_mostly_review_with_tonights_first(client, client_engine, monkeypatch):
    freeze_clock(monkeypatch, "2026-10-05 21:00")
    checkin(client, sleep_hours=8, stress=2, focus=4)
    ids = ids_by_slug(generate(client))
    for slug in ("discriminant", "linear-function", "sequence-limit"):
        pass_node(client, ids[slug])
    move_audits(client_engine, ids["discriminant"], "2026-10-05 10:00")  # this morning
    move_audits(client_engine, ids["linear-function"], "2026-10-02 10:00")  # three days ago: due
    move_audits(client_engine, ids["sequence-limit"], "2026-10-05 20:30")  # half an hour ago: not yet

    body = plan(client)

    reviews = [s for s in body["steps"] if s["kind"] == "review"]
    assert [s["skill_title"] for s in reviews] == ["Discriminant", "Linear Functions"]
    assert reviews[0]["rationale"] == "You learned it today: explain it once more before sleep so it sticks."
    assert reviews[1]["rationale"] == "You explained it 3 days ago: tell it again before it fades."
    assert reviews[0]["minutes"] == 10
    # No challenge in the evening, and judgement only as leaves.
    assert "challenge" not in kinds(body)
    assert body["summary"].startswith("Evening: mostly review.")


def test_late_at_night_one_short_review_at_most(client, client_engine, monkeypatch):
    freeze_clock(monkeypatch, "2026-10-05 23:40")
    ids = ids_by_slug(generate(client))
    for slug in ("discriminant", "linear-function"):
        pass_node(client, ids[slug])
        move_audits(client_engine, ids[slug], "2026-10-02 10:00")

    body = plan(client)

    assert kinds(body) == ["review"]
    assert body["summary"].startswith("It's late: one short review at most, then sleep.")


def test_a_low_day_halves_the_focus_and_drops_challenges(client, monkeypatch):
    freeze_clock(monkeypatch, "2026-10-05 09:00")
    checkin(client, sleep_hours=4, stress=5, focus=1)
    generate(client, "Computer Vision", search_syllabus=False)

    body = plan(client)

    assert (body["condition_flag"], body["focus_budget"]) == ("low", 120)
    assert "challenge" not in kinds(body)
    assert "today's load is halved" in body["summary"]


def test_with_the_focus_used_up_the_day_is_for_rest(client, client_engine, monkeypatch):
    freeze_clock(monkeypatch, "2026-10-05 16:00")
    checkin(client, sleep_hours=4, stress=5, focus=1)  # low: two hours
    ids = ids_by_slug(generate(client))
    for slug in ("discriminant", "linear-function", "sequence-limit"):
        pass_node(client, ids[slug])
        move_audits(client_engine, ids[slug], "2026-10-05 09:00", minutes=45)

    body = plan(client)

    assert body["steps"] == [] and body["focus_left"] == 0 and body["focus_spent"] == 135
    assert "Today's focus is used up (2 h 15 min)." in body["summary"]


def test_the_players_own_numbers_on_a_day_like_today(client, client_engine, monkeypatch):
    freeze_clock(monkeypatch, "2026-10-20 09:00")
    ids = ids_by_slug(generate(client))
    with Session(client_engine) as session:
        for day in range(1, 11):
            session.add(DailyCheckIn(date=at(f"2026-10-{day:02d} 08:00").date(), sleep_hours=8 if day % 2 else 5))
        session.commit()
    # Audits: passed on long nights, failed on short ones.
    for day in range(1, 11):
        audit = start(client, ids["discriminant"] if day % 2 else ids["root-coefficient"])
        answer_turns(client, audit, FIRST, LONG if day % 2 else SHORT)
        with Session(client_engine) as session:
            row = session.get(AuditSession, audit)
            row.created_at = at(f"2026-10-{day:02d} 10:00")
            session.add(row)
            session.commit()
    checkin(client, sleep_hours=5)  # a short night today (it counts among them too)

    body = plan(client)

    assert "On your days with under 6 h of sleep you passed 0% of audits; after 7 h or more, 100% (11 days)." in body["summary"]


def test_a_plan_from_another_time_of_day_is_stale(client, monkeypatch):
    move = freeze_clock(monkeypatch, "2026-10-05 09:00")
    generate(client)
    plan(client)
    assert client.get("/api/plan/current").json()["stale"] is False

    move("2026-10-05 19:00")
    assert client.get("/api/plan/current").json()["stale"] is True
    move("2026-10-06 09:00")
    assert client.get("/api/plan/current").json()["stale"] is True


def test_a_node_that_is_another_course_is_not_a_quest(client, monkeypatch):
    freeze_clock(monkeypatch, "2026-10-05 09:00")
    math = ids_by_slug(generate(client))
    vision = generate(client, "Computer Vision", search_syllabus=False)
    client.put(f"/api/skills/{math['discriminant']}/link", json={"course_id": vision["course"]["id"]})

    body = plan(client)

    assert math["discriminant"] not in [s["skill_id"] for s in body["steps"]]
