"""Material Finder (UT-27) and POST /skills/{id}/search-plan (IT-28)."""

import json

import pytest
from sqlmodel import Session

from app.agents.material_finder import MaterialFinder
from app.llm.mock import MockProvider
from app.models import SearchPlan, SkillNode
from app.search.base import SearchHit
from app.search.mock import MockSearchProvider
from tests.helpers import BrokenProvider, CountingProvider, ScriptedProvider, generate, ids_by_slug, make_principle

GAP = "Could not explain the solutions when the discriminant is negative"
HITS = [SearchHit(f"Title {i}", f"https://real.invalid/{i}", f"Summary {i}") for i in range(5)]


class FixedSearch:
    name = "fixed"

    def __init__(self, hits=HITS, fail=False):
        self.hits, self.fail, self.queries = hits, fail, []

    def search(self, query, limit=5):
        self.queries.append(query)
        if self.fail:
            raise RuntimeError("search is down")
        return self.hits


def scripted(queries=("discriminant negative complex roots", "negative discriminant"), picks=()):
    return ScriptedProvider(
        material_finder=[json.dumps({"queries": list(queries)}), json.dumps({"picks": list(picks)})]
    )


def find(provider, search=None):
    return MaterialFinder(provider, search or FixedSearch()).find("Quadratic Equations", "Description", GAP)


def test_ut27_urls_come_from_the_results_not_from_the_model():
    picks = [{"index": 2, "reason": "Has an example", "url": "https://evil.example/x", "title": "Fake"}]

    queries, items = find(scripted(picks=picks))

    assert queries == ["discriminant negative complex roots", "negative discriminant"]
    assert [(i.title, i.url, i.snippet, i.reason) for i in items] == [("Title 2", "https://real.invalid/2", "Summary 2", "Has an example")]


def test_bad_indices_and_duplicates_are_dropped_and_three_is_the_cap():
    picks = [{"index": i, "reason": "r"} for i in (9, -1, 0, 0, 1, 2, 3, "x", True)]

    _, items = find(scripted(picks=picks))

    assert [i.url[-1] for i in items] == ["0", "1", "2"]


def test_picking_nothing_is_allowed():
    assert find(scripted(picks=[]))[1] == []


def test_a_broken_pick_step_gives_an_empty_list_not_an_error():
    provider = ScriptedProvider(material_finder=[json.dumps({"queries": ["q1", "q2"]}), "garbage"])

    queries, items = find(provider)

    assert queries == ["q1", "q2"] and items == []


def test_results_are_deduplicated_by_url_before_the_pick_step():
    provider = scripted(picks=[{"index": 5, "reason": "r"}])
    _, items = find(provider, FixedSearch())

    # two queries return the same five hits, the pick step still sees five, not ten
    assert items == []
    assert provider.system_prompts("material_finder")[1].count("\n[") == 5


def test_queries_are_capped_at_three_and_deduplicated():
    search = FixedSearch()
    find(scripted(queries=["a", "a", "b", "c", "d"]), search)

    assert search.queries == ["a", "b", "c"]


def test_no_usable_query_is_an_error():
    with pytest.raises(Exception):
        find(scripted(queries=[]))
    with pytest.raises(Exception):
        find(ScriptedProvider(material_finder="nope"))


def test_one_failing_search_is_tolerated_but_all_failing_is_an_error():
    class Flaky(FixedSearch):
        def search(self, query, limit=5):
            if query == "q1":
                raise RuntimeError("down")
            return super().search(query, limit)

    def fresh():
        return ScriptedProvider(material_finder=[json.dumps({"queries": ["q1", "q2"]}), json.dumps({"picks": []})])

    assert find(fresh(), Flaky())[1] == []
    with pytest.raises(RuntimeError):
        find(fresh(), FixedSearch(fail=True))


def test_prompts_carry_the_agent_tag_and_the_gap():
    provider = scripted(picks=[])
    find(provider)

    step1, step2 = provider.system_prompts("material_finder")
    assert step1.startswith("[agent: material_finder]") and f"Gap: {GAP}" in step1
    assert step2.startswith("[agent: material_finder]") and GAP in step2 and "real.invalid" in step2


# ---------------------------------------------------------------- the Mock script, contract 4.6


def test_46_mock_queries_and_first_three_results():
    search = MockSearchProvider()
    queries, items = MaterialFinder(MockProvider(), search).find("Quadratic Equations", "Description", GAP)

    assert queries == [f"Quadratic Equations {GAP[:30]}".strip(), "Quadratic Equations explained"]
    assert [i.url for i in items] == [h.url for h in search.search(queries[0])[:3]]
    assert {i.reason for i in items} == {"Covers this gap directly."}


# ---------------------------------------------------------------- endpoint


def test_it28_without_gap_or_misconception_id_is_400(client):
    ids = ids_by_slug(generate(client))
    expected = {"detail": "A gap or misconception id is required. Search targets a specific gap only."}

    for body in ({}, {"gap": "   "}, {"gap": None}):
        response = client.post(f"/api/skills/{ids['algebra']}/search-plan", json=body)
        assert response.status_code == 400 and response.json() == expected


def test_search_plan_for_a_missing_skill_is_404(client):
    response = client.post("/api/skills/999/search-plan", json={"gap": GAP})

    assert (response.status_code, response.json()) == (404, {"detail": "skill not found"})


def test_search_plan_from_a_gap(client, client_engine):
    ids = ids_by_slug(generate(client))

    response = client.post(f"/api/skills/{ids['quadratic-equation']}/search-plan", json={"gap": f"  {GAP} "})

    assert response.status_code == 200
    body = response.json()
    assert set(body) == {"id", "skill_id", "gap", "queries", "items", "created_at"}
    assert body["gap"] == GAP and body["skill_id"] == ids["quadratic-equation"]
    assert body["queries"] == [f"Quadratic Equations {GAP[:30]}".strip(), "Quadratic Equations explained"]
    assert len(body["items"]) == 3
    assert all(set(i) == {"title", "url", "snippet", "reason"} and i["url"].startswith("https://example.invalid/") for i in body["items"])
    with Session(client_engine) as session:
        assert session.get(SearchPlan, body["id"]).gap == GAP


def test_search_plan_from_a_stored_misconception(client, client_engine):
    ids = ids_by_slug(generate(client))
    with Session(client_engine) as session:
        principle = make_principle(session, session.get(SkillNode, ids["quadratic-equation"]), misconception="No real roots means no solutions")
        principle_id = principle.id

    response = client.post(f"/api/skills/{ids['quadratic-equation']}/search-plan", json={"misconception_id": principle_id})

    assert response.status_code == 200 and response.json()["gap"] == "No real roots means no solutions"


def test_a_missing_or_empty_misconception_is_404(client, client_engine):
    ids = ids_by_slug(generate(client))
    with Session(client_engine) as session:
        empty = make_principle(session, session.get(SkillNode, ids["root-coefficient"]), misconception="  ").id
        none = make_principle(session, session.get(SkillNode, ids["root-coefficient"]), misconception=None).id

    for principle_id in (999, empty, none):
        response = client.post(f"/api/skills/{ids['algebra']}/search-plan", json={"misconception_id": principle_id})
        assert (response.status_code, response.json()) == (404, {"detail": "misconception not found"})


def test_a_gap_wins_over_a_misconception_id(client):
    ids = ids_by_slug(generate(client))

    response = client.post(f"/api/skills/{ids['algebra']}/search-plan", json={"gap": GAP, "misconception_id": 999})

    assert response.status_code == 200 and response.json()["gap"] == GAP


def test_search_failure_is_502(client, monkeypatch):
    ids = ids_by_slug(generate(client))
    monkeypatch.setattr("app.routers.skills.get_provider", lambda agent=None: BrokenProvider())

    response = client.post(f"/api/skills/{ids['algebra']}/search-plan", json={"gap": GAP})

    assert (response.status_code, response.json()) == (502, {"detail": "Material search failed. Please try again."})


def test_search_plan_uses_the_material_finder_provider_twice(client, monkeypatch):
    ids = ids_by_slug(generate(client))
    provider = CountingProvider()
    requested = []
    monkeypatch.setattr("app.routers.skills.get_provider", lambda agent=None: (requested.append(agent), provider)[1])

    client.post(f"/api/skills/{ids['algebra']}/search-plan", json={"gap": GAP})

    assert requested == ["material_finder"] and provider.counts == {"material_finder": 2}
