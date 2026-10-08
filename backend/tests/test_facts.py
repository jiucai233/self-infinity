"""Lasting facts (contract #40): the Fact Keeper after check-ins and chat, the gate in front of it,
the player's own edits, and what the Life Coach is given."""

import json
from datetime import date, datetime, timezone

import pytest
from sqlmodel import Session, select

from app.agents.fact_keeper import Change, parse_changes
from app.models import FactCategory, LifeFact
from app.services import facts
from tests.helpers import BrokenProvider, ScriptedProvider

TODAY = date(2026, 10, 8)


@pytest.fixture(autouse=True)
def fixed_today(monkeypatch):
    monkeypatch.setattr("app.services.life.local_today", lambda: TODAY)
    monkeypatch.setattr("app.services.checkin.local_today", lambda: TODAY)
    monkeypatch.setattr("app.services.facts.local_today", lambda: TODAY)


@pytest.fixture
def session(client_engine):
    with Session(client_engine) as s:
        yield s


@pytest.fixture
def keeper(monkeypatch):
    """The provider the background keeper gets, recording its calls."""
    provider = ScriptedProvider()
    monkeypatch.setattr("app.services.facts.get_provider", lambda agent=None: provider)
    return provider


def life(client) -> dict:
    return client.get("/api/life").json()


def texts(items: list[dict]) -> list[str]:
    return [f["text"] for f in items]


def add(session, text, category=FactCategory.other) -> LifeFact:
    fact = LifeFact(text=text, category=category)
    session.add(fact)
    session.commit()
    session.refresh(fact)
    return fact


# ---------------------------------------------------------------- from a check-in


def test_a_check_in_that_names_an_injury_keeps_it(client):
    client.post("/api/checkins", json={"transcript": "Slept 7 hours. I hurt my knee playing football."})

    body = life(client)
    assert texts(body["facts"]) == ["Knee injury"]
    assert body["facts"][0]["category"] == "health" and body["facts"][0]["source"] == "said"
    assert body["past_facts"] == [] and body["max_facts"] == facts.MAX_FACTS


def test_one_days_things_keep_nothing(client, keeper):
    client.post("/api/checkins", json={"transcript": "Slept 6 hours, had ramen, stressed about work."})

    assert life(client)["facts"] == []
    assert len(keeper.calls_for("fact_keeper")) == 1  # asked (no gate without an OpenAI key), said no


def test_a_manual_check_in_is_not_read(client, keeper):
    client.post("/api/checkins", json={"sleep_hours": 7})
    assert keeper.calls_for("fact_keeper") == []


def test_healed_ends_the_fact_and_keeps_it_as_history(client, keeper):
    client.post("/api/checkins", json={"transcript": "I sprained my ankle."})
    client.post("/api/checkins", json={"transcript": "My ankle is fine now, ran 20 minutes."})

    body = life(client)
    assert body["facts"] == []
    (past,) = body["past_facts"]
    assert past["text"] == "Ankle injury" and past["ended_at"] is not None
    # The keeper saw the list with ids, so it could name the one to end.
    assert "· Ankle injury" in keeper.system_prompts("fact_keeper")[-1]


def test_an_update_ends_the_old_fact_and_the_new_one_points_back(client, client_engine, monkeypatch):
    with Session(client_engine) as session:
        old = add(session, "Knee injury; no running", FactCategory.health)
    update = json.dumps({"changes": [{"op": "update", "id": old.id, "text": "Knee recovering; short runs only"}]})
    monkeypatch.setattr("app.services.facts.get_provider", lambda agent=None: ScriptedProvider(fact_keeper=update))

    client.post("/api/checkins", json={"transcript": "Physio says short runs are fine now."})

    body = life(client)
    (now,) = body["facts"]
    assert (now["text"], now["category"], now["replaces_id"]) == ("Knee recovering; short runs only", "health", old.id)
    assert texts(body["past_facts"]) == ["Knee injury; no running"]


def test_a_failing_keeper_changes_nothing_and_the_check_in_still_saves(client, monkeypatch):
    monkeypatch.setattr("app.services.facts.get_provider", lambda agent=None: BrokenProvider())

    response = client.post("/api/checkins", json={"transcript": "I hurt my knee. Slept 7 hours."})

    assert response.status_code == 200 and response.json()["checkin"]["sleep_hours"] == 7
    assert life(client)["facts"] == []


# ---------------------------------------------------------------- from chat and voice


def test_a_plain_chat_message_is_read(client, keeper):
    client.post("/api/chat", json={"message": "fyi I work night shifts this month"})
    assert texts(life(client)["facts"]) == ["Works night shifts"]


def test_a_chat_check_in_is_read(client, keeper):
    client.post("/api/chat", json={"message": "check in: slept 6 hours, I'm vegetarian btw"})
    assert texts(life(client)["facts"]) == ["Vegetarian"]


def test_asking_for_a_plan_is_not_read(client, keeper):
    client.post("/api/chat", json={"message": "what should I study today?"})
    assert keeper.calls_for("fact_keeper") == []


def test_the_voice_guide_check_in_and_its_log_are_read_user_lines_only(client, keeper):
    client.post("/api/chat/act", json={"intent": "checkin", "said": "Slept 7 hours, I hurt my wrist."})
    client.post(
        "/api/chat/log",
        json={"messages": [
            {"role": "assistant", "content": "Are you vegan?"},
            {"role": "user", "content": "I have exams until Friday."},
        ]},
    )

    assert sorted(texts(life(client)["facts"])) == ["Exams until Friday", "Wrist injury"]
    said = [m[-1]["content"] for m in keeper.calls_for("fact_keeper")]
    assert said[-1] == "<said>\nI have exams until Friday.\n</said>"


# ---------------------------------------------------------------- the gate


def gate(answer, confidence=0.9, seen=None):
    def decide(input_text, questions):
        if seen is not None:
            seen.append(input_text)
        assert [q["name"] for q in questions] == ["lasting"]
        return {"lasting": (answer, confidence)}

    return decide


def test_a_confident_no_skips_the_keeper(session):
    provider, seen = ScriptedProvider(), []
    add(session, "Works night shifts", FactCategory.schedule)

    assert facts.keep_facts(session, "slept 6 hours", provider, decide=gate("no", seen=seen)) == []
    assert provider.calls_for("fact_keeper") == []
    assert "Works night shifts" in seen[0] and seen[0].endswith("The learner said:\nslept 6 hours")


@pytest.mark.parametrize("decide", [gate("yes"), gate("no", confidence=0.6), lambda *_: 1 / 0])
def test_yes_an_unsure_no_or_a_failing_gate_asks_the_keeper(session, decide):
    provider = ScriptedProvider()
    touched = facts.keep_facts(session, "I hurt my back", provider, decide=decide)
    assert [f.text for f in touched] == ["Back injury"]


# ---------------------------------------------------------------- applying changes


def test_unknown_ids_repeats_and_a_full_list_are_dropped(session):
    for i in range(facts.MAX_FACTS - 1):
        add(session, f"fact {i}")
    ended = add(session, "old")
    facts.apply_changes(session, [Change("end", fact_id=ended.id)])

    touched = facts.apply_changes(session, [
        Change("end", fact_id=999),
        Change("end", fact_id=ended.id),  # already ended
        Change("add", text="FACT 0"),  # repeats one
        Change("add", text="new one"),  # fills the list
        Change("add", text="one too many"),
    ])

    assert [f.text for f in touched] == ["new one"]
    assert len(facts.current_facts(session)) == facts.MAX_FACTS


def test_malformed_changes_are_dropped():
    changes = parse_changes({"changes": [
        {"op": "add", "category": "health", "text": "  Knee   injury "},
        {"op": "add", "category": "mood", "text": "x"},  # unknown category: other
        {"op": "update", "id": "3", "text": "x"},
        {"op": "update", "id": True, "text": "x"},
        {"op": "update", "id": 3},
        {"op": "delete", "id": 3},
        {"op": "end", "id": 4},
        "end 5",
    ]})
    assert changes == [
        Change("add", category=FactCategory.health, text="Knee injury"),
        Change("add", category=None, text="x"),
        Change("end", fact_id=4),
    ]


# ---------------------------------------------------------------- the player's own edits


def test_adding_editing_ending_bringing_back_and_deleting(client):
    added = client.post("/api/life/facts", json={"category": "constraint", "text": " No screens after 11 "}).json()
    assert (added["text"], added["category"], added["source"]) == ("No screens after 11", "constraint", "manual")
    fid = added["id"]

    edited = client.patch(f"/api/life/facts/{fid}", json={"text": "No screens after 23:00"}).json()
    assert (edited["id"], edited["text"], edited["category"], edited["ended_at"]) == (fid, "No screens after 23:00", "constraint", None)

    client.patch(f"/api/life/facts/{fid}", json={"ended": True})
    assert texts(life(client)["past_facts"]) == ["No screens after 23:00"]
    client.patch(f"/api/life/facts/{fid}", json={"ended": False})
    assert texts(life(client)["facts"]) == ["No screens after 23:00"]

    assert client.delete(f"/api/life/facts/{fid}").status_code == 204
    assert life(client)["facts"] == [] and client.delete(f"/api/life/facts/{fid}").status_code == 404
    assert client.patch(f"/api/life/facts/{fid}", json={"ended": True}).status_code == 404


def test_deleting_a_replaced_fact_unlinks_the_one_that_replaced_it(client, client_engine):
    with Session(client_engine) as session:
        old_id = add(session, "old").id
        facts.apply_changes(session, [Change("update", fact_id=old_id, text="new")])

    client.delete(f"/api/life/facts/{old_id}")

    with Session(client_engine) as session:
        (new,) = session.exec(select(LifeFact)).all()
        assert (new.text, new.replaces_id) == ("new", None)


def test_a_full_list_refuses_another_and_bringing_one_back(client, client_engine):
    with Session(client_engine) as session:
        for i in range(facts.MAX_FACTS):
            add(session, f"fact {i}")
        ended_id = add(session, "ended").id
        facts.apply_changes(session, [Change("end", fact_id=ended_id)])

    response = client.post("/api/life/facts", json={"text": "one more"})
    assert response.status_code == 409 and response.json()["detail"].startswith("You can keep 20 lasting facts")
    assert client.patch(f"/api/life/facts/{ended_id}", json={"ended": False}).status_code == 409


@pytest.mark.parametrize("text", ["   ", "x" * 121])
def test_a_fact_needs_text_that_fits(client, text):
    assert client.post("/api/life/facts", json={"text": text}).status_code == 422


# ---------------------------------------------------------------- what the Life Coach sees


def test_the_coach_sees_what_holds_now_never_what_ended(client, client_engine, monkeypatch):
    provider = ScriptedProvider()
    monkeypatch.setattr("app.routers.life.get_provider", lambda agent=None: provider)
    client.post("/api/life/facts", json={"category": "health", "text": "Knee injury; no running"})
    with Session(client_engine) as session:
        gone = add(session, "Exams until Friday", FactCategory.schedule)
        facts.apply_changes(session, [Change("end", fact_id=gone.id)])

    client.post("/api/life/advice")

    (system,) = provider.system_prompts("life_coach")
    sent = json.loads(system.split("<facts>\n")[1].split("\n</facts>")[0])
    assert sent["lasting"] == [{"category": "health", "text": "Knee injury; no running", "since": datetime.now(timezone.utc).strftime("%Y-%m")}]
    assert "Exams" not in system and "Never advise against them" in system
