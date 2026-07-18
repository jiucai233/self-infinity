from unittest.mock import patch

from app.llm.base import Message


class BrokenProvider:
    name = "broken"

    def complete(self, messages: list[Message]) -> str:
        raise RuntimeError("provider is down")


def _root_skill_id(client) -> int:
    skills = client.get("/api/skills").json()
    return next(s["id"] for s in skills if s["slug"] == "big-o")


def test_generate_tree_returns_502_on_provider_failure(client):
    with patch("app.routers.skills.get_provider", return_value=BrokenProvider()):
        resp = client.post("/api/skills/generate", json={"topic": "B 树"})
    assert resp.status_code == 502
    assert resp.json()["detail"] == "技能树规划失败，请稍后重试"


def test_submit_turn_returns_502_on_provider_failure(client):
    skill_id = _root_skill_id(client)
    start = client.post(f"/api/skills/{skill_id}/audits")
    audit_id = start.json()["session"]["id"]

    with patch("app.routers.audits.get_provider", return_value=BrokenProvider()):
        resp = client.post(f"/api/audits/{audit_id}/turns", json={"content": "一些回答"})
    assert resp.status_code == 502
    assert resp.json()["detail"] == "审计官暂时无法响应，请稍后重试"

    session = client.get(f"/api/skills").json()
    assert any(s["id"] == skill_id for s in session)


def test_submit_reflection_returns_502_on_provider_failure(client):
    skill_id = _root_skill_id(client)
    start = client.post(f"/api/skills/{skill_id}/audits")
    audit_id = start.json()["session"]["id"]

    weak_answer = "不知道，反正大概就是这样吧。"
    client.post(f"/api/audits/{audit_id}/turns", json={"content": weak_answer})
    client.post(f"/api/audits/{audit_id}/turns", json={"content": weak_answer})
    verdict = client.post(f"/api/audits/{audit_id}/turns", json={"content": weak_answer}).json()
    assert verdict["passed"] is False

    with patch("app.routers.audits.get_provider", return_value=BrokenProvider()):
        resp = client.post(
            f"/api/audits/{audit_id}/reflection", json={"reflection": "下次先想清楚原理再开口。"}
        )
    assert resp.status_code == 502
    assert resp.json()["detail"] == "原则蒸馏失败，请稍后重试"
