"""Recommender (UT-26) and the plan endpoints (IT-27)."""

import json

import pytest
from sqlmodel import Session

from app.agents.recommender import Candidate, Recommender, RecommenderError
from app.llm.mock import MockProvider
from app.models import EdgeKind, SkillStatus
from tests.helpers import (
    BrokenProvider,
    CountingProvider,
    ScriptedProvider,
    generate,
    ids_by_slug,
    link,
    make_course,
    make_skill,
    pass_node,
    set_status,
)

REASON = "Prerequisites checked — you can take this on now."
HINT = "Explain the why before the definition."


def candidates(*ids: int, position="leaf") -> list[Candidate]:
    return [Candidate(skill_id=i, title=f"Node {i}", position=position, tier="medium") for i in ids]


def reply(*ids, extra=()) -> ScriptedProvider:
    steps = [{"skill_id": i, "rationale": f"r{i}", "focus_hint": f"h{i}"} for i in ids]
    return ScriptedProvider(recommender=json.dumps({"steps": [*steps, *extra]}))


def recommend(provider, available, flag="normal"):
    return Recommender(provider).recommend(available, "medium", [], flag)


def test_ut26_an_unknown_skill_id_is_dropped():
    steps = recommend(reply(1, 99, 2), candidates(1, 2, 3))

    assert [s.skill_id for s in steps] == [1, 2]


def test_duplicates_are_dropped_and_at_most_five_are_kept():
    steps = recommend(reply(1, 1, 2, 3, 4, 5, 6, 7), candidates(*range(1, 8)))

    assert [s.skill_id for s in steps] == [1, 2, 3, 4, 5]


def test_string_ids_are_accepted_but_junk_is_skipped():
    provider = ScriptedProvider(recommender=json.dumps({"steps": [
        {"skill_id": "2", "rationale": "a", "focus_hint": "b"}, {"skill_id": True}, {"skill_id": None}, {"x": 1}]}))

    assert [s.skill_id for s in recommend(provider, candidates(1, 2))] == [2]


@pytest.mark.parametrize("raw", ["not json", '{"steps": 3}', '{"steps": []}', '{"steps": [{"skill_id": 99}]}'])
def test_no_usable_step_is_an_error(raw):
    with pytest.raises(RecommenderError):
        recommend(ScriptedProvider(recommender=raw), candidates(1, 2))


def test_the_prompt_lists_nodes_tier_clusters_and_condition():
    provider = reply(1)
    Recommender(provider).recommend(
        [Candidate(1, "Quadratic Functions", "leaf", "hard", ["Quadratic Equations"])], "medium", [], "low"
    )

    (system,) = provider.system_prompts("recommender")
    assert system.startswith("[agent: recommender]")
    nodes = json.loads(system.split("<available_nodes>\n")[1].split("\n</available_nodes>")[0])
    assert nodes == [{"skill_id": 1, "title": "Quadratic Functions", "position": "leaf", "tier": "hard", "unmet_requires": ["Quadratic Equations"]}]
    assert "Suggested difficulty tier: medium" in system and "Condition: low" in system


# ---------------------------------------------------------------- the Mock script, contract 4.6


def test_46_mock_takes_the_first_five_available_nodes_by_id():
    steps = recommend(MockProvider(), candidates(9, 3, 5, 1, 7, 8, 2))

    assert [s.skill_id for s in steps] == [1, 2, 3, 5, 7]
    assert {(s.rationale, s.focus_hint) for s in steps} == {(REASON, HINT)}


def test_46_mock_puts_leaves_first_when_the_condition_is_low():
    available = [Candidate(1, "a", "branch", "easy"), Candidate(2, "b", "leaf", "easy"),
                 Candidate(3, "c", "root", "easy"), Candidate(4, "d", "leaf", "easy")]

    assert [s.skill_id for s in recommend(MockProvider(), available, "low")] == [2, 4, 1, 3]
    assert [s.skill_id for s in recommend(MockProvider(), available, "normal")] == [1, 2, 3, 4]


# ---------------------------------------------------------------- endpoints


def test_it27_plan_with_no_available_node_is_400(client):
    response = client.post("/api/plan/generate")

    assert response.status_code == 400
    assert response.json() == {"detail": "No node is available yet. Generate a course or pass an existing node first."}
    assert client.get("/api/plan/current").json() is None


def test_plan_generation_returns_and_stores_a_study_plan(client):
    # One node per course is open (the next in its learning order), so three courses.
    ids = ids_by_slug(generate(client))
    pass_node(client, ids["discriminant"])
    cooking = ids_by_slug(generate(client, "Cooking"))
    chess = ids_by_slug(generate(client, "Chess"))

    response = client.post("/api/plan/generate")

    assert response.status_code == 200
    plan = response.json()
    assert set(plan) == {"id", "suggested_tier", "context_bucket", "created_at", "steps"}
    assert plan["suggested_tier"] in ("easy", "medium", "hard") and plan["context_bucket"] in ("low", "mid", "high")
    assert [s["skill_id"] for s in plan["steps"]] == [ids["root-coefficient"], cooking["core-concepts-1"], chess["core-concepts-1"]]
    assert plan["steps"][0] == {"skill_id": ids["root-coefficient"], "course_id": 1, "skill_title": "Roots and Coefficients",
                                "node_type": "concept", "rationale": REASON, "focus_hint": HINT}
    assert client.get("/api/plan/current").json() == plan


def test_current_plan_is_the_latest_one(client):
    ids = ids_by_slug(generate(client))
    first = client.post("/api/plan/generate").json()
    pass_node(client, ids["discriminant"])
    generate(client, "Cooking")
    second = client.post("/api/plan/generate").json()

    assert second["id"] != first["id"] and len(second["steps"]) == 2 and len(first["steps"]) == 1
    assert client.get("/api/plan/current").json() == second


def test_plan_is_capped_at_five_steps_over_several_courses(client, client_engine):
    with Session(client_engine) as session:
        course = make_course(session)
        for i in range(8):
            make_skill(session, course, f"n{i}", f"Node {i}")

    assert len(client.post("/api/plan/generate").json()["steps"]) == 5


def test_only_available_nodes_are_offered(client, client_engine):
    with Session(client_engine) as session:
        course = make_course(session)
        a_id = make_skill(session, course, "a", "A", status=SkillStatus.available).id
        make_skill(session, course, "b", "B", status=SkillStatus.locked)
        make_skill(session, course, "c", "C", status=SkillStatus.mastered)

    assert [s["skill_id"] for s in client.post("/api/plan/generate").json()["steps"]] == [a_id]


def test_unmet_requires_reach_the_recommender(client, client_engine, monkeypatch):
    with Session(client_engine) as session:
        course = make_course(session)
        first = make_skill(session, course, "f", "First")
        second = make_skill(session, course, "s", "Second")
        link(session, first, second, EdgeKind.requires)
        first_id, second_id = first.id, second.id
    provider = reply(first_id, second_id)
    monkeypatch.setattr("app.routers.plan.get_provider", lambda agent=None: provider)

    client.post("/api/plan/generate")

    (system,) = provider.system_prompts("recommender")
    nodes = json.loads(system.split("<available_nodes>\n")[1].split("\n</available_nodes>")[0])
    assert {n["title"]: n["unmet_requires"] for n in nodes} == {"First": [], "Second": ["First"]}


def test_hallucinated_ids_are_dropped_by_the_endpoint(client, monkeypatch):
    ids = ids_by_slug(generate(client))
    monkeypatch.setattr("app.routers.plan.get_provider", lambda agent=None: reply(999, ids["discriminant"]))

    steps = client.post("/api/plan/generate").json()["steps"]

    assert [s["skill_id"] for s in steps] == [ids["discriminant"]]


@pytest.mark.parametrize("provider", [BrokenProvider(), ScriptedProvider(recommender="nope"), reply(999)])
def test_plan_failure_is_502_and_nothing_is_stored(client, monkeypatch, provider):
    generate(client)
    monkeypatch.setattr("app.routers.plan.get_provider", lambda agent=None: provider)

    response = client.post("/api/plan/generate")

    assert response.status_code == 502
    assert response.json() == {"detail": "Plan generation failed. Please try again."}
    assert client.get("/api/plan/current").json() is None


def test_plan_generation_asks_the_recommender_once(client, monkeypatch):
    generate(client)
    provider = CountingProvider()
    requested = []
    monkeypatch.setattr("app.routers.plan.get_provider", lambda agent=None: (requested.append(agent), provider)[1])

    client.post("/api/plan/generate")

    assert requested == ["recommender"] and provider.counts == {"recommender": 1}
