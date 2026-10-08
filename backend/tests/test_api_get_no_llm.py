"""AD-1：读接口永远不调用 LLM（也不调用搜索）。IT-29。"""

import pytest

from app.llm.mock import MockProvider
from app.llm.openai_compatible import OpenAICompatibleProvider
from app.search.mock import MockSearchProvider
from tests.helpers import fail_node, generate, ids_by_slug, pass_node

GET_ENDPOINTS = [
    "/api/health",
    "/api/courses",
    "/api/courses/1/map",
    "/api/skills",
    "/api/skills?course_id=1",
    "/api/skills/recommendation",
    "/api/principles",
    "/api/graph",
    "/api/narrator/briefing",
    "/api/plan/current",
    "/api/chat/history",
    "/api/chat/suggestions",
    "/api/checkins/today",
    "/api/skills/1/overview",
    "/api/audits",
    "/api/profile",
    "/api/journal",
    "/api/goals",
    "/api/me",
]


@pytest.fixture(name="populated")
def populated_fixture(client):
    """A course, a pass, a fail and a principle, so every GET has something to return."""
    ids = ids_by_slug(generate(client, "Math"))
    pass_node(client, ids["discriminant"])
    pass_node(client, ids["root-coefficient"])
    audit_id = fail_node(client, ids["quadratic-equation"])
    assert client.post(f"/api/audits/{audit_id}/reflection", json={"reflection": "A misconception"}).status_code == 200
    return ids


@pytest.mark.parametrize("path", GET_ENDPOINTS)
def test_it29_get_endpoints_make_no_llm_or_search_call(client, populated, monkeypatch, path):
    def forbidden(*args, **kwargs):
        raise AssertionError("a GET endpoint called out to an LLM or the search provider")

    monkeypatch.setattr(MockProvider, "complete", forbidden)
    monkeypatch.setattr(OpenAICompatibleProvider, "complete", forbidden)
    monkeypatch.setattr(MockSearchProvider, "search", forbidden)

    response = client.get(path)

    assert response.status_code == 200, (path, response.text)


def test_it29_the_forbidden_call_really_would_fail_a_post(client, populated, monkeypatch):
    """Guards the guard: with the same patch in place, an LLM endpoint does blow up."""

    def forbidden(*args, **kwargs):
        raise AssertionError("blocked")

    monkeypatch.setattr(MockProvider, "complete", forbidden)

    response = client.post("/api/skills/clarify", json={"topic": "Statistics"})

    # The Clarifier swallows provider errors by design, so this is "no clarification", not a crash...
    assert response.json() == {"needs_clarification": False, "questions": []}
    # ...but a turn really does reach the provider and fails with the auditor-unavailable 502.
    ids = populated
    audit = client.post(f"/api/skills/{ids['quadratic-equation']}/audits").json()["session"]["id"]
    assert client.post(f"/api/audits/{audit}/turns", json={"content": "Hello"}).status_code == 502
