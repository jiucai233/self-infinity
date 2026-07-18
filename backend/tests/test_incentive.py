def _root_skill_id(client) -> int:
    skills = client.get("/api/skills").json()
    return next(s["id"] for s in skills if s["slug"] == "big-o")


GOOD_ANSWER = (
    "因为每次调用规模减半，所以是对数级；如果输入不满足有序这个前提条件，"
    "这个方法就不成立，是有明确边界的，不是任何情况下都对。"
)
WEAK_ANSWER = "不知道，反正大概就是这样吧。"


def test_passing_audit_creates_reward_event(client):
    skill_id = _root_skill_id(client)
    start = client.post(f"/api/skills/{skill_id}/audits")
    audit_id = start.json()["session"]["id"]

    client.post(f"/api/audits/{audit_id}/turns", json={"content": GOOD_ANSWER})
    client.post(f"/api/audits/{audit_id}/turns", json={"content": GOOD_ANSWER})
    verdict = client.post(f"/api/audits/{audit_id}/turns", json={"content": GOOD_ANSWER}).json()

    assert verdict["type"] == "verdict"
    assert verdict["passed"] is True
    assert verdict["reward_amount"] is not None
    assert verdict["reward_amount"] > 0
    assert verdict["reward_multiplier"] is not None
    assert verdict["reward_multiplier"] > 0


def test_failing_audit_creates_no_reward_event(client):
    skill_id = _root_skill_id(client)
    start = client.post(f"/api/skills/{skill_id}/audits")
    audit_id = start.json()["session"]["id"]

    client.post(f"/api/audits/{audit_id}/turns", json={"content": WEAK_ANSWER})
    client.post(f"/api/audits/{audit_id}/turns", json={"content": WEAK_ANSWER})
    verdict = client.post(f"/api/audits/{audit_id}/turns", json={"content": WEAK_ANSWER}).json()

    assert verdict["type"] == "verdict"
    assert verdict["passed"] is False
    assert verdict["reward_amount"] is None
    assert verdict["reward_multiplier"] is None


def test_focus_latest_404_then_populated_after_audit(client):
    resp = client.get("/api/focus/latest")
    assert resp.status_code == 404

    skill_id = _root_skill_id(client)
    start = client.post(f"/api/skills/{skill_id}/audits")
    audit_id = start.json()["session"]["id"]

    client.post(f"/api/audits/{audit_id}/turns", json={"content": GOOD_ANSWER})
    client.post(f"/api/audits/{audit_id}/turns", json={"content": GOOD_ANSWER})
    verdict = client.post(f"/api/audits/{audit_id}/turns", json={"content": GOOD_ANSWER}).json()
    assert verdict["type"] == "verdict"

    resp = client.get("/api/focus/latest")
    assert resp.status_code == 200
    body = resp.json()
    assert body["source"] == "audit_engagement"
    assert body["focus_score"] is not None
    assert 0 <= body["focus_score"] <= 100
    assert body["ended_at"] is not None
