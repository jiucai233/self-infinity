def test_health(client):
    resp = client.get("/api/health")
    assert resp.status_code == 200
    assert resp.json()["llm_provider"] == "mock"


def test_skills_seeded(client):
    resp = client.get("/api/skills")
    assert resp.status_code == 200
    skills = resp.json()
    assert len(skills) == 4
    root = next(s for s in skills if s["slug"] == "big-o")
    assert root["status"] == "available"
    child = next(s for s in skills if s["slug"] == "recursion")
    assert child["status"] == "locked"


def _root_skill_id(client) -> int:
    skills = client.get("/api/skills").json()
    return next(s["id"] for s in skills if s["slug"] == "big-o")


def test_audit_pass_unlocks_child(client):
    skill_id = _root_skill_id(client)

    start = client.post(f"/api/skills/{skill_id}/audits")
    assert start.status_code == 200
    audit_id = start.json()["session"]["id"]

    good_answer = (
        "因为每次调用规模减半，所以是对数级；如果输入不满足有序这个前提条件，"
        "这个方法就不成立，是有明确边界的，不是任何情况下都对。"
    )

    r1 = client.post(f"/api/audits/{audit_id}/turns", json={"content": good_answer})
    assert r1.json()["type"] == "probe"

    r2 = client.post(f"/api/audits/{audit_id}/turns", json={"content": good_answer})
    assert r2.json()["type"] == "probe"

    r3 = client.post(f"/api/audits/{audit_id}/turns", json={"content": good_answer})
    verdict = r3.json()
    assert verdict["type"] == "verdict"
    assert verdict["passed"] is True
    assert len(verdict["unlocked_skill_ids"]) == 2

    skills = client.get("/api/skills").json()
    for slug in ("recursion", "graph-bfs"):
        node = next(s for s in skills if s["slug"] == slug)
        assert node["status"] == "available"


def test_audit_fail_then_reflection_creates_principle(client):
    skill_id = _root_skill_id(client)

    start = client.post(f"/api/skills/{skill_id}/audits")
    audit_id = start.json()["session"]["id"]

    weak_answer = "不知道，反正大概就是这样吧。"
    client.post(f"/api/audits/{audit_id}/turns", json={"content": weak_answer})
    client.post(f"/api/audits/{audit_id}/turns", json={"content": weak_answer})
    verdict = client.post(f"/api/audits/{audit_id}/turns", json={"content": weak_answer}).json()
    assert verdict["passed"] is False

    reflection = client.post(
        f"/api/audits/{audit_id}/reflection", json={"reflection": "下次先想清楚原理再开口。"}
    )
    assert reflection.status_code == 200
    body = reflection.json()
    assert body["title"]
    assert body["body"]

    principles = client.get("/api/principles").json()
    assert len(principles) == 1


def test_locked_skill_cannot_start_audit(client):
    skills = client.get("/api/skills").json()
    locked = next(s for s in skills if s["slug"] == "recursion")
    resp = client.post(f"/api/skills/{locked['id']}/audits")
    assert resp.status_code == 400
