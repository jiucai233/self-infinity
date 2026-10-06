"""Life-as-a-game layer (contract section 6): profile, journal, reflection suggestions and answering."""

from datetime import datetime, timezone

import pytest
from sqlalchemy import create_engine, text
from sqlmodel import Session, select

import app.db as app_db
from app.llm.mock import MockProvider
from app.models import ChatMessage, JournalEntry
from app.schemas import REFLECTION_PROMPTS
from tests.helpers import freeze_clock, generate

P_WEEK, P_PUTOFF, P_TWO_HOURS, P_VISION, P_IGNORING, P_IMAGE, P_ALIVE = REFLECTION_PROMPTS

ACK = "Noted. It's in your journal."


def test_the_seven_prompts_are_the_contract_strings():
    assert REFLECTION_PROMPTS == (
        "Who are you becoming this week? One sentence.",
        "What are you putting off right now?",
        "Looking at the last two hours, what were you really after?",
        "Is today pulling you toward your vision or your anti-vision?",
        "What matters most that you've been ignoring?",
        "Today, were you guarding an image of yourself or going after what you want?",
        "When did you feel most alive today, and when least?",
    )


# ---------------------------------------------------------------- profile


def test_a_fresh_profile_is_empty(client):
    response = client.get("/api/profile")

    assert response.status_code == 200
    assert response.json() == {
        "identity": "", "vision": "", "anti_vision": "", "rules": [], "updated_at": None, "onboarded": False
    }


def test_put_saves_and_get_returns_it(client):
    body = {"identity": "I explain from first principles.", "vision": "A lab of my own", "anti_vision": "Drifting",
            "rules": ["No phone before the first audit", "Sleep by 1"]}

    saved = client.put("/api/profile", json=body)

    assert saved.status_code == 200
    got = client.get("/api/profile").json()
    assert saved.json() == got
    assert {k: got[k] for k in body} == body
    assert got["updated_at"].endswith(("Z", "+00:00"))


def test_put_is_a_partial_update_omitted_fields_are_kept(client):
    client.put("/api/profile", json={"identity": "I", "vision": "V", "anti_vision": "A", "rules": ["r1"]})

    client.put("/api/profile", json={"vision": "V2"})
    after = client.get("/api/profile").json()

    assert (after["identity"], after["vision"], after["anti_vision"], after["rules"]) == ("I", "V2", "A", ["r1"])


def test_put_an_empty_body_changes_nothing_but_succeeds(client):
    client.put("/api/profile", json={"identity": "I"})

    response = client.put("/api/profile", json={})

    assert response.status_code == 200 and response.json()["identity"] == "I"


def test_a_field_can_be_cleared_with_an_empty_string_and_empty_rules(client):
    client.put("/api/profile", json={"identity": "I", "rules": ["r"]})

    after = client.put("/api/profile", json={"identity": "", "rules": []}).json()

    assert after["identity"] == "" and after["rules"] == []


def test_updated_at_moves_on_every_save(client):
    first = client.put("/api/profile", json={"identity": "a"}).json()["updated_at"]
    second = client.put("/api/profile", json={"identity": "b"}).json()["updated_at"]

    assert datetime.fromisoformat(second) >= datetime.fromisoformat(first)


def test_there_is_only_ever_one_profile_row(client, client_engine):
    from app.models import Profile

    client.put("/api/profile", json={"identity": "a"})
    client.put("/api/profile", json={"vision": "b"})

    with Session(client_engine) as session:
        assert len(session.exec(select(Profile)).all()) == 1


@pytest.mark.parametrize("field", ["identity", "vision", "anti_vision"])
def test_text_limit_is_280_characters(client, field):
    assert client.put("/api/profile", json={field: "x" * 280}).status_code == 200
    assert client.put("/api/profile", json={field: "x" * 281}).status_code == 422


def test_an_over_limit_put_changes_nothing(client):
    client.put("/api/profile", json={"identity": "keep"})

    assert client.put("/api/profile", json={"identity": "x" * 281, "vision": "new"}).status_code == 422
    assert client.get("/api/profile").json()["identity"] == "keep"
    assert client.get("/api/profile").json()["vision"] == ""


def test_text_is_trimmed_before_the_limit(client):
    response = client.put("/api/profile", json={"identity": "  " + "x" * 280 + "  "})

    assert response.status_code == 200 and response.json()["identity"] == "x" * 280


def test_at_most_five_rules(client):
    assert client.put("/api/profile", json={"rules": [f"r{i}" for i in range(5)]}).status_code == 200
    assert client.put("/api/profile", json={"rules": [f"r{i}" for i in range(6)]}).status_code == 422


def test_each_rule_is_at_most_120_characters(client):
    assert client.put("/api/profile", json={"rules": ["x" * 120]}).status_code == 200
    assert client.put("/api/profile", json={"rules": ["x" * 121]}).status_code == 422


def test_blank_rules_are_dropped_and_do_not_count_toward_the_limit(client):
    body = {"rules": ["a", "", "   ", "b", " c ", "d", "e", "\n"]}  # 5 real rules among blanks

    response = client.put("/api/profile", json=body)

    assert response.status_code == 200 and response.json()["rules"] == ["a", "b", "c", "d", "e"]


@pytest.mark.parametrize("body", [
    {"identity": None}, {"rules": None}, {"rules": "not a list"}, {"identity": 5}, {"rules": [1]},
])
def test_wrong_types_and_nulls_are_422(client, body):
    assert client.put("/api/profile", json=body).status_code == 422


def test_profile_endpoints_never_call_the_llm(client, monkeypatch):
    def forbidden(*a, **k):
        raise AssertionError("LLM called")

    monkeypatch.setattr(MockProvider, "complete", forbidden)

    assert client.put("/api/profile", json={"identity": "x"}).status_code == 200
    assert client.get("/api/profile").status_code == 200
    assert client.get("/api/journal").status_code == 200


# ---------------------------------------------------------------- journal


def add_entries(client_engine, n):
    with Session(client_engine) as session:
        for i in range(n):
            session.add(JournalEntry(prompt=f"p{i}", answer=f"a{i}", created_at=datetime(2026, 10, 5, 0, i, tzinfo=timezone.utc)))
        session.commit()


def test_an_empty_journal_is_an_empty_list(client):
    response = client.get("/api/journal")

    assert response.status_code == 200 and response.json() == []


def test_journal_is_newest_first_with_the_contract_shape(client, client_engine):
    add_entries(client_engine, 3)

    body = client.get("/api/journal").json()

    assert [e["answer"] for e in body] == ["a2", "a1", "a0"]
    assert set(body[0]) == {"id", "prompt", "answer", "created_at"}
    assert datetime.fromisoformat(body[0]["created_at"]) == datetime(2026, 10, 5, 0, 2, tzinfo=timezone.utc)


def test_journal_ties_on_time_break_newest_id_first(client, client_engine):
    same = datetime(2026, 10, 5, tzinfo=timezone.utc)
    with Session(client_engine) as session:
        session.add(JournalEntry(prompt="p", answer="first", created_at=same))
        session.add(JournalEntry(prompt="p", answer="second", created_at=same))
        session.commit()

    assert [e["answer"] for e in client.get("/api/journal").json()] == ["second", "first"]


def test_journal_default_limit_is_20_and_limit_is_honoured(client, client_engine):
    add_entries(client_engine, 25)

    assert len(client.get("/api/journal").json()) == 20
    limited = client.get("/api/journal?limit=3").json()
    assert [e["answer"] for e in limited] == ["a24", "a23", "a22"]
    assert len(client.get("/api/journal?limit=100").json()) == 25


@pytest.mark.parametrize("limit", [0, 101, -1, "abc"])
def test_journal_limit_out_of_range_is_422(client, limit):
    assert client.get(f"/api/journal?limit={limit}").status_code == 422


# ---------------------------------------------------------------- reflection windows (suggestions item 1)


def checked_in(client):
    assert client.post("/api/checkins", json={"sleep_hours": 7}).status_code == 200


def first_item(client):
    return client.get("/api/chat/suggestions").json()["suggestions"][0]


@pytest.mark.parametrize(
    "when, prompt",
    [
        ("2026-10-05 03:00", P_WEEK),
        ("2026-10-05 08:30", P_WEEK),
        ("2026-10-05 10:59", P_WEEK),
        ("2026-10-05 11:00", P_PUTOFF),
        ("2026-10-05 13:29", P_PUTOFF),
        ("2026-10-05 13:30", P_TWO_HOURS),
        ("2026-10-05 15:14", P_TWO_HOURS),
        ("2026-10-05 15:15", P_VISION),
        ("2026-10-05 16:59", P_VISION),
        ("2026-10-05 17:00", P_IGNORING),
        ("2026-10-05 19:29", P_IGNORING),
        ("2026-10-05 19:30", P_IMAGE),
        ("2026-10-05 20:59", P_IMAGE),
        ("2026-10-05 21:00", P_ALIVE),
        ("2026-10-05 23:59", P_ALIVE),
        ("2026-10-06 00:00", P_ALIVE),
        ("2026-10-06 01:30", P_ALIVE),
        ("2026-10-06 02:59", P_ALIVE),
        ("2026-10-06 03:00", P_WEEK),
    ],
)
def test_every_window_boundary(client, monkeypatch, when, prompt):
    freeze_clock(monkeypatch, when)
    checked_in(client)

    assert first_item(client) == {"label": prompt, "message": "", "skill_id": None, "reflection": True}


def test_without_a_checkin_item_one_is_the_checkin_chip_at_any_time(client, monkeypatch):
    for when in ("2026-10-05 08:00", "2026-10-05 23:00", "2026-10-06 01:00"):
        freeze_clock(monkeypatch, when)
        item = first_item(client)
        assert item["label"] == "How was your day?" and item["reflection"] is False


def test_only_the_reflection_item_is_flagged(client, monkeypatch):
    freeze_clock(monkeypatch, "2026-10-05 12:00")
    generate(client, "Math")
    checked_in(client)

    items = client.get("/api/chat/suggestions").json()["suggestions"]

    assert [i["reflection"] for i in items] == [True, False]
    assert all(set(i) == {"label", "message", "skill_id", "reflection"} for i in items)


def test_reflection_is_omitted_once_answered_in_that_window(client, monkeypatch):
    freeze_clock(monkeypatch, "2026-10-05 12:00")
    generate(client, "Math")
    checked_in(client)
    assert first_item(client)["label"] == P_PUTOFF

    client.post("/api/chat", json={"message": "The taxes.", "reflection_prompt": P_PUTOFF})

    items = client.get("/api/chat/suggestions").json()["suggestions"]
    assert [i["reflection"] for i in items] == [False]  # only "continue learning" is left


def test_answering_one_window_does_not_hide_the_next(client, monkeypatch):
    move = freeze_clock(monkeypatch, "2026-10-05 12:00")
    checked_in(client)
    client.post("/api/chat", json={"message": "x", "reflection_prompt": P_PUTOFF})

    move("2026-10-05 13:30")

    assert first_item(client)["label"] == P_TWO_HOURS


def test_an_answer_from_yesterday_does_not_hide_todays_prompt(client, client_engine, monkeypatch):
    freeze_clock(monkeypatch, "2026-10-05 12:00")
    checked_in(client)
    with Session(client_engine) as session:
        # 2026-10-04 12:00 KST = 03:00 UTC
        session.add(JournalEntry(prompt=P_PUTOFF, answer="old", created_at=datetime(2026, 10, 4, 3, 0, tzinfo=timezone.utc)))
        session.commit()

    assert first_item(client)["label"] == P_PUTOFF


def test_the_day_boundary_uses_kst_not_utc(client, client_engine, monkeypatch):
    freeze_clock(monkeypatch, "2026-10-05 08:00")  # KST 08:00 = 2026-10-04 23:00 UTC
    checked_in(client)
    with Session(client_engine) as session:
        # answered at 07:00 KST on the 5th = 22:00 UTC on the 4th: still "today" in KST
        session.add(JournalEntry(prompt=P_WEEK, answer="a", created_at=datetime(2026, 10, 4, 22, 0, tzinfo=timezone.utc)))
        session.commit()

    assert client.get("/api/chat/suggestions").json()["suggestions"][0]["reflection"] is False


def test_evening_answered_before_midnight_stays_answered_after_midnight(client, monkeypatch):
    move = freeze_clock(monkeypatch, "2026-10-05 22:00")
    checked_in(client)
    assert first_item(client)["label"] == P_ALIVE
    client.post("/api/chat", json={"message": "dinner", "reflection_prompt": P_ALIVE})

    for when in ("2026-10-05 23:30", "2026-10-06 00:30", "2026-10-06 02:59"):
        move(when)
        client.post("/api/checkins", json={"sleep_hours": 7})  # after midnight the check-in is a new day's
        # after midnight it is still the previous evening's window, and it was answered
        assert first_item(client)["reflection"] is False, when


def test_evening_answered_after_midnight_is_answered_for_the_previous_evening(client, monkeypatch):
    move = freeze_clock(monkeypatch, "2026-10-06 01:00")
    client.post("/api/checkins", json={"sleep_hours": 6})  # a check-in dated the 6th
    assert first_item(client)["label"] == P_ALIVE
    client.post("/api/chat", json={"message": "late", "reflection_prompt": P_ALIVE})

    move("2026-10-06 02:00")
    assert first_item(client)["reflection"] is False
    move("2026-10-06 03:00")  # a new window: the morning prompt
    assert first_item(client)["label"] == P_WEEK


def test_the_next_evening_is_a_fresh_window(client, monkeypatch):
    move = freeze_clock(monkeypatch, "2026-10-06 01:00")
    client.post("/api/checkins", json={"sleep_hours": 6})
    client.post("/api/chat", json={"message": "late", "reflection_prompt": P_ALIVE})  # evening of the 5th

    move("2026-10-06 21:00")  # evening of the 6th: the 01:00 answer must not count

    assert first_item(client)["label"] == P_ALIVE


def test_after_midnight_item_one_follows_the_calendar_checkin(client, monkeypatch):
    move = freeze_clock(monkeypatch, "2026-10-05 21:30")
    checked_in(client)
    client.post("/api/chat", json={"message": "a", "reflection_prompt": P_ALIVE})

    # the check-in is dated the 5th; at 00:10 on the 6th there is no check-in for "today" yet
    move("2026-10-06 00:10")
    assert first_item(client)["label"] == "How was your day?"


# ---------------------------------------------------------------- chat: answering a reflection


def post_reflection(client, prompt=P_PUTOFF, message="  The taxes.  "):
    response = client.post("/api/chat", json={"message": message, "reflection_prompt": prompt})
    assert response.status_code == 200, response.text
    return response.json()["messages"]


def test_answering_returns_prompt_user_ack_in_order(client):
    messages = post_reflection(client)

    assert [(m["role"], m["agent"], m["content"]) for m in messages] == [
        ("assistant", "front_desk", P_PUTOFF),
        ("user", None, "The taxes."),
        ("assistant", "front_desk", ACK),
    ]
    assert all(m["action"] is None for m in messages)
    assert messages[0]["id"] < messages[1]["id"] < messages[2]["id"]


def test_answering_writes_a_journal_entry(client):
    post_reflection(client)

    entries = client.get("/api/journal").json()

    assert len(entries) == 1
    assert entries[0]["prompt"] == P_PUTOFF and entries[0]["answer"] == "The taxes."


def test_the_three_messages_are_in_the_chat_history(client):
    post_reflection(client)

    history = client.get("/api/chat/history").json()

    assert [m["content"] for m in history] == [P_PUTOFF, "The taxes.", ACK]


@pytest.mark.parametrize("prompt", REFLECTION_PROMPTS)
def test_every_prompt_is_accepted(client, prompt):
    assert [m["content"] for m in post_reflection(client, prompt)][0] == prompt


@pytest.mark.parametrize("prompt", ["Who are you?", "", " " + REFLECTION_PROMPTS[0], REFLECTION_PROMPTS[0].lower(), 5])
def test_an_unknown_prompt_is_422_and_saves_nothing(client, client_engine, prompt):
    response = client.post("/api/chat", json={"message": "hi", "reflection_prompt": prompt})

    assert response.status_code == 422
    with Session(client_engine) as session:
        assert session.exec(select(ChatMessage)).all() == []
        assert session.exec(select(JournalEntry)).all() == []


def test_a_blank_answer_is_422(client):
    response = client.post("/api/chat", json={"message": "   ", "reflection_prompt": P_PUTOFF})

    assert response.status_code == 422


def test_an_explicit_null_prompt_is_a_normal_chat_message(client):
    response = client.post("/api/chat", json={"message": "Hello", "reflection_prompt": None})

    assert response.status_code == 200
    assert response.json()["messages"][1]["content"] == "Sure. What would you like to do today?"


def test_no_llm_runs_when_answering_a_reflection(client, monkeypatch):
    def forbidden(*a, **k):
        raise AssertionError("LLM called")

    monkeypatch.setattr(MockProvider, "complete", forbidden)
    monkeypatch.setattr("app.routers.chat.get_provider", forbidden)

    assert len(post_reflection(client, message="I want to learn Math")) == 3  # a keyword would route to a course


def test_a_reflection_answer_does_not_trigger_any_intent(client, client_engine):
    post_reflection(client, message="I want to learn Math and log my day")

    from app.models import Course, DailyCheckIn

    with Session(client_engine) as session:
        assert session.exec(select(Course)).all() == []
        assert session.exec(select(DailyCheckIn)).all() == []


def test_uploads_are_ignored_when_answering_a_reflection(client):
    response = client.post("/api/chat", json={"message": "a", "reflection_prompt": P_PUTOFF, "upload_ids": [999]})

    assert response.status_code == 200 and len(response.json()["messages"]) == 3


def test_answering_the_same_prompt_twice_makes_two_entries(client):
    post_reflection(client, message="one")
    post_reflection(client, message="two")

    assert [e["answer"] for e in client.get("/api/journal").json()] == ["two", "one"]


# ---------------------------------------------------------------- storage: fresh and existing databases


def test_init_db_adds_the_new_tables_to_an_existing_database(tmp_path, monkeypatch):
    """An existing dev DB (no profile/journal tables yet) gains them without losing data."""
    from sqlalchemy import inspect
    from sqlmodel import SQLModel

    from app.models import Course, Profile

    engine = create_engine(f"sqlite:///{tmp_path / 'old.db'}")
    old_tables = [t for name, t in SQLModel.metadata.tables.items() if name not in ("profile", "journalentry")]
    SQLModel.metadata.create_all(engine, tables=old_tables)
    with Session(engine) as session:
        session.add(Course(topic="Kept"))
        session.commit()
    assert not {"profile", "journalentry"} & set(inspect(engine).get_table_names())

    monkeypatch.setattr(app_db, "engine", engine)
    app_db.init_db()
    app_db.init_db()  # idempotent

    assert {"profile", "journalentry"} <= set(inspect(engine).get_table_names())
    with Session(engine) as session:
        assert session.exec(select(Course)).one().topic == "Kept"
        session.add(Profile(id=1, identity="x"))
        session.add(JournalEntry(prompt="p", answer="a"))
        session.commit()
        assert session.connection().execute(text("select count(*) from journalentry")).scalar() == 1


def test_init_db_on_a_fresh_database_creates_everything(tmp_path, monkeypatch):
    from sqlalchemy import inspect

    engine = create_engine(f"sqlite:///{tmp_path / 'fresh.db'}")
    monkeypatch.setattr(app_db, "engine", engine)

    app_db.init_db()

    assert {"profile", "journalentry", "chatmessage"} <= set(inspect(engine).get_table_names())
