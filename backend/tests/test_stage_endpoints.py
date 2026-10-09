"""Stage UI endpoints (contract section 5): xp in the facts, checkins/today, skill overview,
audit summaries, and the chat table on fresh and existing databases."""

from datetime import timedelta

from sqlalchemy import inspect, text
from sqlmodel import Session, SQLModel, create_engine, select
from sqlmodel.pool import StaticPool

import app.db as app_db
from app.models import DailyCheckIn, RewardEvent
from app.utils import local_today
from tests.helpers import (
    MATH_ORDER,
    LONG,
    FIRST,
    answer_turns,
    fail_node,
    generate,
    ids_by_slug,
    pass_node,
    start,
)

# ---------------------------------------------------------------- xp


def xp(client) -> dict:
    return client.get("/api/narrator/briefing").json()["facts"]["xp"]


def test_xp_starts_at_level_one_with_nothing(client):
    assert xp(client) == {"total": 0, "level": 1, "level_progress": 0.0}


def test_xp_total_is_the_sum_of_rewards_and_progress_follows_mastered_nodes(client):
    ids = ids_by_slug(generate(client, "Math"))
    rewards = []
    for slug in MATH_ORDER[:2]:
        rewards.append(pass_node(client, ids[slug])["reward_amount"])

    assert xp(client) == {"total": sum(rewards), "level": 1, "level_progress": 0.4}

    for slug in MATH_ORDER[2:4]:
        rewards.append(pass_node(client, ids[slug])["reward_amount"])
    assert xp(client)["level_progress"] == 0.8 and xp(client)["level"] == 1

    rewards.append(pass_node(client, ids[MATH_ORDER[4]])["reward_amount"])  # the 5th mastered node
    assert xp(client) == {"total": sum(rewards), "level": 2, "level_progress": 0.0}

    pass_node(client, ids[MATH_ORDER[5]])
    assert (xp(client)["level"], xp(client)["level_progress"]) == (2, 0.2)


def test_a_failed_audit_gives_no_xp(client):
    ids = ids_by_slug(generate(client, "Math"))
    fail_node(client, ids["discriminant"])

    assert xp(client) == {"total": 0, "level": 1, "level_progress": 0.0}


def test_xp_level_is_the_incentive_engines_level(client, client_engine):
    from app.services.incentive import global_level

    ids = ids_by_slug(generate(client, "Math"))
    for slug in MATH_ORDER[:5]:
        pass_node(client, ids[slug])

    with Session(client_engine) as session:
        assert global_level(session) == xp(client)["level"] == 2


def test_xp_counts_reward_rows_directly(client, client_engine):
    pass_node(client, ids_by_slug(generate(client, "Math"))["discriminant"])
    with Session(client_engine) as session:
        session.add(RewardEvent(session_id=1, amount=100, multiplier=1.1))
        session.commit()
        expected = sum(r.amount for r in session.exec(select(RewardEvent)).all())

    assert xp(client)["total"] == expected


def test_xp_is_in_the_chat_briefing_and_the_narrate_response_too(client):
    pass_node(client, ids_by_slug(generate(client, "Math"))["discriminant"])

    narrated = client.post("/api/narrator/narrate").json()

    assert narrated["facts"]["xp"] == xp(client) and narrated["facts"]["xp"]["total"] > 0


# ---------------------------------------------------------------- GET /api/checkins/today


def test_today_is_null_with_200_when_there_is_no_checkin(client):
    response = client.get("/api/checkins/today")

    assert response.status_code == 200 and response.json() is None


def test_today_returns_todays_record(client):
    client.post("/api/checkins", json={"sleep_hours": 7, "exercised": True})

    body = client.get("/api/checkins/today").json()

    assert body == {
        "date": local_today().isoformat(), "sleep_hours": 7, "exercised": True, "diet_note": None,
        "focus": None, "stress": None, "transcript": None, "source": "manual",
        "sleep_quality": None, "exercise_minutes": None, "weight_kg": None,
    }


def test_today_follows_the_replaced_record(client):
    client.post("/api/checkins", json={"sleep_hours": 5})
    client.post("/api/checkins", json={"sleep_hours": 8})

    assert client.get("/api/checkins/today").json()["sleep_hours"] == 8


def test_an_earlier_days_checkin_is_not_today(client, client_engine):
    with Session(client_engine) as session:
        session.add(DailyCheckIn(date=local_today() - timedelta(days=1), sleep_hours=9))
        session.commit()

    assert client.get("/api/checkins/today").json() is None


def test_today_uses_the_kst_date_not_the_utc_date(client, client_engine, monkeypatch):
    from datetime import date

    monkeypatch.setattr("app.services.checkin.local_today", lambda: date(2026, 10, 5))
    with Session(client_engine) as session:
        session.add(DailyCheckIn(date=date(2026, 10, 5), sleep_hours=6))
        session.add(DailyCheckIn(date=date(2026, 10, 4), sleep_hours=9))
        session.commit()

    assert client.get("/api/checkins/today").json()["sleep_hours"] == 6


def test_today_is_computed_from_the_configured_timezone(client, monkeypatch):
    from datetime import datetime
    from zoneinfo import ZoneInfo

    from app.config import settings

    monkeypatch.setattr(settings, "app_timezone", "Asia/Seoul")
    client.post("/api/checkins", json={"stress": 2})

    assert client.get("/api/checkins/today").json()["date"] == datetime.now(ZoneInfo("Asia/Seoul")).date().isoformat()


# ---------------------------------------------------------------- GET /api/skills/{id}/overview


def test_overview_404(client):
    response = client.get("/api/skills/999/overview")

    assert response.status_code == 404 and response.json() == {"detail": "skill not found"}


def test_overview_of_a_fresh_node_has_empty_lists(client):
    generated = generate(client, "Math")
    ids = ids_by_slug(generated)

    body = client.get(f"/api/skills/{ids['high-school-math']}/overview").json()

    assert set(body) == {"skill", "course", "contains_parents", "requires", "audits", "materials"}
    assert body["skill"]["title"] == "High School Math" and body["skill"]["status"] == "locked"
    assert body["course"] == generated["course"]
    assert body["contains_parents"] == [] and body["requires"] == []
    assert body["audits"] == [] and body["materials"] == []


def test_overview_lists_parents_and_requires_with_reasons(client):
    ids = ids_by_slug(generate(client, "Math"))

    body = client.get(f"/api/skills/{ids['quadratic-function']}/overview").json()

    assert [p["slug"] for p in body["contains_parents"]] == ["functions"]
    assert [(r["skill"]["slug"], r["reason"]) for r in body["requires"]] == [
        ("quadratic-equation", "The x-intercepts of a quadratic function are the roots of a quadratic equation."),
        ("linear-function", "You need the graph of a linear function first."),
    ]
    assert set(body["requires"][0]) == {"skill", "reason"}
    assert set(body["requires"][0]["skill"]) == {
        "id", "course_id", "slug", "title", "description", "status", "node_type", "mastery_score",
        "unexpanded", "tested_out", "linked_course_id",
    }


def test_overview_puts_the_main_parent_first_when_there_are_several(client):
    ids = ids_by_slug(generate(client, "Math"))

    body = client.get(f"/api/skills/{ids['sequence-limit']}/overview").json()

    assert [p["slug"] for p in body["contains_parents"]] == ["calculus", "sequences"]


def test_overview_requires_only_lists_incoming_edges(client):
    ids = ids_by_slug(generate(client, "Math"))

    body = client.get(f"/api/skills/{ids['quadratic-equation']}/overview").json()

    assert body["requires"] == []  # quadratic-equation is required BY quadratic-function, it requires nothing


def test_overview_audits_are_this_nodes_newest_first(client):
    ids = ids_by_slug(generate(client, "Math"))
    pass_node(client, ids["discriminant"])
    first = fail_node(client, ids["root-coefficient"])
    second = start(client, ids["root-coefficient"])
    _probe, verdict = answer_turns(client, second, FIRST, LONG)
    assert verdict["passed"]

    audits = client.get(f"/api/skills/{ids['root-coefficient']}/overview").json()["audits"]

    assert [(a["id"], a["status"], a["skill_id"], a["skill_title"]) for a in audits] == [
        (second, "passed", ids["root-coefficient"], "Roots and Coefficients"),
        (first, "failed", ids["root-coefficient"], "Roots and Coefficients"),
    ]
    assert audits[0]["score"] == verdict["score"] and audits[1]["score"] == 45
    assert set(audits[0]) == {"id", "skill_id", "skill_title", "status", "score", "created_at", "test_out"}


def test_overview_materials_are_this_nodes_search_plans_newest_first(client):
    ids = ids_by_slug(generate(client, "Math"))
    plans = [
        client.post(f"/api/skills/{ids['algebra']}/search-plan", json={"gap": gap}).json()
        for gap in ("First gap", "Second gap")
    ]
    client.post(f"/api/skills/{ids['functions']}/search-plan", json={"gap": "Another node"})

    materials = client.get(f"/api/skills/{ids['algebra']}/overview").json()["materials"]

    assert [m["id"] for m in materials] == [plans[1]["id"], plans[0]["id"]]
    assert materials[0] == plans[1]  # the same SearchPlan shape as endpoint 17
    assert client.get(f"/api/skills/{ids['functions']}/overview").json()["materials"][0]["gap"] == "Another node"


def test_overview_an_audit_active_session_is_listed_without_a_score(client):
    ids = ids_by_slug(generate(client, "Math"))
    audit_id = start(client, ids["discriminant"])

    audits = client.get(f"/api/skills/{ids['discriminant']}/overview").json()["audits"]

    assert audits == [{**audits[0], "id": audit_id, "status": "active", "score": None}]


# ---------------------------------------------------------------- GET /api/audits


def test_audits_list_is_empty_at_first(client):
    response = client.get("/api/audits")

    assert response.status_code == 200 and response.json() == []


def test_audits_list_is_newest_first_across_courses(client):
    a = ids_by_slug(generate(client, "Math"))
    b = ids_by_slug(generate(client, "Cooking"))
    first = fail_node(client, a["discriminant"])
    second = fail_node(client, b["core-concepts-1"])
    third = fail_node(client, a["discriminant"])

    body = client.get("/api/audits").json()

    assert [x["id"] for x in body] == [third, second, first]
    assert [x["skill_title"] for x in body] == ["Discriminant", "Core Concepts 1", "Discriminant"]
    assert body[0] == {
        "id": third, "skill_id": a["discriminant"], "skill_title": "Discriminant", "status": "failed",
        "score": 45, "created_at": body[0]["created_at"], "test_out": False,
    }
    assert body[0]["created_at"].endswith("Z") or body[0]["created_at"].endswith("+00:00")


def test_audits_list_limit_and_default(client):
    ids = ids_by_slug(generate(client, "Math"))
    created = [fail_node(client, ids["discriminant"]) for _ in range(23)]

    assert len(client.get("/api/audits").json()) == 20  # the default
    assert [a["id"] for a in client.get("/api/audits?limit=3").json()] == created[::-1][:3]
    assert len(client.get("/api/audits?limit=100").json()) == 23


def test_audits_list_limit_out_of_range_is_422(client):
    for limit in (0, 101, -5, "x"):
        assert client.get(f"/api/audits?limit={limit}").status_code == 422


def test_audits_list_mixes_statuses(client):
    ids = ids_by_slug(generate(client, "Math"))
    pass_node(client, ids["discriminant"])
    start(client, ids["root-coefficient"])

    statuses = [a["status"] for a in client.get("/api/audits").json()]

    assert statuses == ["active", "passed"]


# ---------------------------------------------------------------- the chat table


def new_engine():
    return create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)


def test_chat_table_is_created_on_a_fresh_database(monkeypatch):
    engine = new_engine()
    monkeypatch.setattr(app_db, "engine", engine)

    app_db.init_db()

    columns = {c["name"]: c["nullable"] for c in inspect(engine).get_columns("chatmessage")}
    assert set(columns) == {"id", "role", "content", "agent", "action_json", "created_at"}
    assert columns["agent"] and columns["action_json"]  # nullable


def test_chat_table_is_added_to_an_existing_database(monkeypatch):
    engine = new_engine()
    SQLModel.metadata.create_all(engine)
    with engine.begin() as conn:
        conn.execute(text("DROP TABLE chatmessage"))
        conn.execute(text("INSERT INTO course (topic, settings_json, created_at) VALUES ('Old course', '{}', '2026-01-01')"))
    monkeypatch.setattr(app_db, "engine", engine)

    app_db.init_db()

    assert "chatmessage" in inspect(engine).get_table_names()
    with engine.connect() as conn:
        assert conn.execute(text("SELECT COUNT(*) FROM course")).scalar() == 1  # existing data untouched
