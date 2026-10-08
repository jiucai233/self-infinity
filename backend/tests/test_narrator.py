"""Narrator (UT-28), GET /narrator/briefing (IT-26) and POST /narrator/narrate."""

import json
from datetime import date, timedelta

import pytest
from sqlmodel import Session, select

from app.agents.narrator import MAX_NARRATIVE, Narrator, NarratorError
from app.llm.mock import MockProvider
from app.models import DailyCheckIn, NarratorBriefing
from app.schemas import ProfileFacts
from tests.helpers import BrokenProvider, CountingProvider, ScriptedProvider, fail_node, generate, ids_by_slug, pass_node

EMPTY_FACTS = ProfileFacts.model_validate(
    {
        "nodes": {"total": 0, "mastered": 0, "available": 0, "locked": 0},
        "audits": {"total": 0, "passed": 0, "failed": 0},
        "misconception_clusters": [],
        "condition": {"days": 0, "avg_sleep_hours": None, "avg_stress": None, "flag": "unknown"},
    }
)
FACTS = ProfileFacts.model_validate(
    {
        "nodes": {"total": 12, "mastered": 4, "available": 3, "locked": 5},
        "audits": {"total": 6, "passed": 4, "failed": 2},
        "misconception_clusters": [
            {"label": "No real roots means no solutions", "occurrences": 2, "skills": ["Quadratic Equations", "Quadratic Functions"],
             "cross_skill": True, "principle_ids": [7, 9]}
        ],
        "condition": {"days": 3, "avg_sleep_hours": 5.3, "avg_stress": None, "flag": "low"},
    }
)


def narrator_reply(narrative) -> ScriptedProvider:
    return ScriptedProvider(narrator=json.dumps({"narrative": narrative}, ensure_ascii=False))


def test_ut28_valid_output_returns_the_narrative():
    assert Narrator(narrator_reply("  You've cleared 4 of 12 nodes. ")).narrate(FACTS) == "You've cleared 4 of 12 nodes."


def test_the_prompt_carries_the_facts_as_json():
    provider = narrator_reply("x")
    Narrator(provider).narrate(FACTS)

    (system,) = provider.system_prompts("narrator")
    assert system.startswith("[agent: narrator]")
    facts = system.split("<facts>\n")[1].split("\n</facts>")[0]
    assert json.loads(facts) == FACTS.model_dump()


@pytest.mark.parametrize("bad", ["", "   ", None, 5])
def test_an_empty_or_non_text_narrative_is_an_error(bad):
    with pytest.raises(NarratorError):
        Narrator(narrator_reply(bad)).narrate(FACTS)


def test_non_json_output_is_an_error():
    with pytest.raises(NarratorError):
        Narrator(ScriptedProvider(narrator="oops")).narrate(FACTS)


def test_a_narrative_over_400_characters_is_cut():
    narrative = Narrator(narrator_reply("Abcde fghij. " * 100)).narrate(FACTS)

    assert 0 < len(narrative) <= MAX_NARRATIVE
    assert narrative.endswith(".")


# ---------------------------------------------------------------- the Mock script, contract 4.6


def test_46_mock_narrator_full_sentence_set():
    assert Narrator(MockProvider()).narrate(FACTS) == (
        "You've cleared 4 of 12 nodes. "
        "The misconception “No real roots means no solutions” showed up 2 times "
        "in Quadratic Equations, Quadratic Functions. "
        "Average sleep over the last 3 days: 5.3 h."
    )


def test_46_mock_narrator_without_sleep_data_leaves_that_sentence_out():
    assert Narrator(MockProvider()).narrate(EMPTY_FACTS) == "You've cleared 0 of 0 nodes."


def test_46_mock_narrator_is_cut_to_400():
    many = FACTS.model_copy(deep=True)
    many.misconception_clusters = many.misconception_clusters * 30

    assert len(Narrator(MockProvider()).narrate(many)) <= 400


# ---------------------------------------------------------------- endpoints


def test_it26_briefing_before_any_narration_has_facts_and_a_null_narrative(client):
    response = client.get("/api/narrator/briefing")

    assert response.status_code == 200
    body = response.json()
    assert body["narrative"] is None and body["narrative_generated_at"] is None
    assert body["facts"]["nodes"] == {"total": 0, "mastered": 0, "available": 0, "locked": 0}
    assert body["facts"]["condition"]["flag"] == "unknown"


def test_narrate_saves_the_narrative_and_the_briefing_returns_it(client, client_engine):
    ids = ids_by_slug(generate(client))
    pass_node(client, ids["discriminant"])

    narrated = client.post("/api/narrator/narrate")

    assert narrated.status_code == 200
    body = narrated.json()
    assert body["narrative"] == "You've cleared 1 of 12 nodes."
    assert body["narrative_generated_at"].endswith(("Z", "+00:00"))
    assert client.get("/api/narrator/briefing").json() == body
    with Session(client_engine) as session:
        assert len(session.exec(select(NarratorBriefing)).all()) == 1


def test_facts_are_fresh_while_the_narrative_stays_cached(client):
    ids = ids_by_slug(generate(client))
    first = client.post("/api/narrator/narrate").json()
    pass_node(client, ids["discriminant"])

    briefing = client.get("/api/narrator/briefing").json()

    assert briefing["facts"]["nodes"]["mastered"] == 1
    assert briefing["narrative"] == first["narrative"] == "You've cleared 0 of 12 nodes."


def test_the_latest_narrative_wins(client):
    client.post("/api/narrator/narrate")
    ids = ids_by_slug(generate(client))
    pass_node(client, ids["discriminant"])

    assert client.post("/api/narrator/narrate").json()["narrative"] == "You've cleared 1 of 12 nodes."
    assert client.get("/api/narrator/briefing").json()["narrative"] == "You've cleared 1 of 12 nodes."


def test_narrate_failure_is_502_and_the_previous_narrative_survives(client, monkeypatch):
    client.post("/api/narrator/narrate")
    monkeypatch.setattr("app.routers.narrator.get_provider", lambda agent=None: BrokenProvider())

    response = client.post("/api/narrator/narrate")

    assert response.status_code == 502
    assert response.json() == {"detail": "Briefing generation failed. Please try again."}
    assert client.get("/api/narrator/briefing").json()["narrative"] == "You've cleared 0 of 0 nodes."


def test_narrate_uses_the_narrator_provider_once(client, monkeypatch):
    provider = CountingProvider()
    requested = []
    monkeypatch.setattr("app.routers.narrator.get_provider", lambda agent=None: (requested.append(agent), provider)[1])

    client.post("/api/narrator/narrate")

    assert requested == ["narrator"] and provider.counts == {"narrator": 1}


def test_briefing_reports_the_condition_and_clusters(client, client_engine):
    ids = ids_by_slug(generate(client))
    pass_node(client, ids["discriminant"])
    pass_node(client, ids["root-coefficient"])
    audit_id = fail_node(client, ids["quadratic-equation"])
    client.post(f"/api/audits/{audit_id}/reflection", json={"reflection": "I thought no real roots meant no solutions"})
    with Session(client_engine) as session:
        for day, sleep in enumerate((5, 5, 6)):
            session.add(DailyCheckIn(date=date(2026, 10, 1) + timedelta(days=day), sleep_hours=sleep))
        session.commit()

    facts = client.get("/api/narrator/briefing").json()["facts"]

    assert facts["condition"] == {"days": 3, "avg_sleep_hours": 5.3, "avg_stress": None, "flag": "low"}
    (cluster,) = facts["misconception_clusters"]
    assert cluster["skills"] == ["Quadratic Equations"] and cluster["cross_skill"] is False and len(cluster["principle_ids"]) == 1
    assert facts["audits"] == {"total": 3, "passed": 2, "failed": 1}
