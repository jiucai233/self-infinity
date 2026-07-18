def _root_skill_id(client) -> int:
    skills = client.get("/api/skills").json()
    return next(s["id"] for s in skills if s["slug"] == "big-o")


def test_generate_tree_rejects_empty_topic(client):
    resp = client.post("/api/skills/generate", json={"topic": ""})
    assert resp.status_code == 422


def test_generate_tree_rejects_whitespace_topic(client):
    resp = client.post("/api/skills/generate", json={"topic": "   "})
    assert resp.status_code == 422


def test_submit_turn_rejects_empty_content(client):
    skill_id = _root_skill_id(client)
    start = client.post(f"/api/skills/{skill_id}/audits")
    audit_id = start.json()["session"]["id"]

    resp = client.post(f"/api/audits/{audit_id}/turns", json={"content": ""})
    assert resp.status_code == 422


def test_submit_turn_rejects_whitespace_content(client):
    skill_id = _root_skill_id(client)
    start = client.post(f"/api/skills/{skill_id}/audits")
    audit_id = start.json()["session"]["id"]

    resp = client.post(f"/api/audits/{audit_id}/turns", json={"content": "   "})
    assert resp.status_code == 422


def test_submit_reflection_rejects_empty_reflection(client):
    skill_id = _root_skill_id(client)
    start = client.post(f"/api/skills/{skill_id}/audits")
    audit_id = start.json()["session"]["id"]

    weak_answer = "不知道，反正大概就是这样吧。"
    client.post(f"/api/audits/{audit_id}/turns", json={"content": weak_answer})
    client.post(f"/api/audits/{audit_id}/turns", json={"content": weak_answer})
    client.post(f"/api/audits/{audit_id}/turns", json={"content": weak_answer})

    resp = client.post(f"/api/audits/{audit_id}/reflection", json={"reflection": ""})
    assert resp.status_code == 422


def test_submit_reflection_rejects_whitespace_reflection(client):
    skill_id = _root_skill_id(client)
    start = client.post(f"/api/skills/{skill_id}/audits")
    audit_id = start.json()["session"]["id"]

    weak_answer = "不知道，反正大概就是这样吧。"
    client.post(f"/api/audits/{audit_id}/turns", json={"content": weak_answer})
    client.post(f"/api/audits/{audit_id}/turns", json={"content": weak_answer})
    client.post(f"/api/audits/{audit_id}/turns", json={"content": weak_answer})

    resp = client.post(f"/api/audits/{audit_id}/reflection", json={"reflection": "   "})
    assert resp.status_code == 422
