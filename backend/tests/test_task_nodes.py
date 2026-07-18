def test_elephant_in_fridge_root_is_task_not_concept(client):
    nodes = client.post(
        "/api/skills/generate", json={"topic": "我要把一个大象放到冰箱里"}
    ).json()
    root = next(n for n in nodes if n["parent_id"] is None)
    assert root["node_type"] == "task"


def test_task_node_passes_without_deep_explanation(client):
    nodes = client.post(
        "/api/skills/generate", json={"topic": "我要把一个大象放到冰箱里"}
    ).json()
    root = next(n for n in nodes if n["parent_id"] is None)

    start = client.post(f"/api/skills/{root['id']}/audits")
    audit_id = start.json()["session"]["id"]
    # 任务型节点开场问题应该问"打算怎么做"，不是"从零讲给我听"
    assert "怎么做" in start.json()["opening_question"]

    concrete_answer = "打开冰箱门，把大象放进去，再把门关上。"
    r1 = client.post(f"/api/audits/{audit_id}/turns", json={"content": concrete_answer})
    assert r1.json()["type"] == "probe"

    r2 = client.post(f"/api/audits/{audit_id}/turns", json={"content": concrete_answer})
    verdict = r2.json()
    assert verdict["type"] == "verdict"
    assert verdict["passed"] is True


def test_task_node_fails_on_hollow_answer(client):
    nodes = client.post(
        "/api/skills/generate", json={"topic": "我要把一个大象放到冰箱里"}
    ).json()
    root = next(n for n in nodes if n["parent_id"] is None)

    start = client.post(f"/api/skills/{root['id']}/audits")
    audit_id = start.json()["session"]["id"]

    hollow_answer = "随便弄弄应该可以吧。"
    client.post(f"/api/audits/{audit_id}/turns", json={"content": hollow_answer})
    verdict = client.post(f"/api/audits/{audit_id}/turns", json={"content": hollow_answer}).json()
    assert verdict["passed"] is False


def test_concept_topic_still_gets_full_feynman_protocol(client):
    nodes = client.post("/api/skills/generate", json={"topic": "B 树"}).json()
    root = next(n for n in nodes if n["parent_id"] is None)
    assert root["node_type"] == "concept"

    start = client.post(f"/api/skills/{root['id']}/audits")
    assert "从零开始" in start.json()["opening_question"]
