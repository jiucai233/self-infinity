from app.agents.clarifier import Clarifier, ClarifyResult
from app.llm.mock import MockProvider


def test_clarify_vague_topic_returns_questions(client):
    resp = client.post("/api/skills/clarify", json={"topic": "做饭"})
    assert resp.status_code == 200
    data = resp.json()
    assert data["needs_clarification"] is True
    assert 1 <= len(data["questions"]) <= 2


def test_clarify_specific_topic_skips_questions(client):
    resp = client.post("/api/skills/clarify", json={"topic": "B 树"})
    assert resp.status_code == 200
    data = resp.json()
    assert data["needs_clarification"] is False
    assert data["questions"] == []


def test_clarify_reinforcement_learning_is_vague(client):
    resp = client.post("/api/skills/clarify", json={"topic": "强化学习"})
    assert resp.status_code == 200
    data = resp.json()
    assert data["needs_clarification"] is True
    assert len(data["questions"]) >= 1


class _BrokenProvider:
    name = "broken"

    def complete(self, messages):
        return "this is not json"


def test_clarifier_falls_back_when_llm_output_malformed():
    result = Clarifier(_BrokenProvider()).clarify("随便什么主题")
    assert result == ClarifyResult(needs_clarification=False, questions=[])


def test_clarify_endpoint_rejects_blank_topic(client):
    resp = client.post("/api/skills/clarify", json={"topic": "   "})
    assert resp.status_code == 422


def test_mock_provider_clarify_matches_known_vague_list():
    result = Clarifier(MockProvider()).clarify("我要学编程")
    assert result.needs_clarification is True
    assert len(result.questions) <= 2
