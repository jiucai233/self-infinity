from sqlmodel import Session, select

from app.models import SkillNode, SkillStatus


def _unlock(engine, skill_id: int) -> None:
    """生成出来的非根节点默认 locked，直接开审计会 400。

    这些测试关心的是开场问题的形状，不是解锁规则，所以直接把状态改开。
    """
    with Session(engine) as session:
        skill = session.get(SkillNode, skill_id)
        skill.status = SkillStatus.available
        session.add(skill)
        session.commit()


def test_elephant_in_fridge_root_is_task_not_concept(client):
    nodes = client.post(
        "/api/skills/generate", json={"topic": "我要把一个大象放到冰箱里"}
    ).json()["nodes"]
    root = next(n for n in nodes if n["parent_id"] is None)
    assert root["node_type"] == "task"


def test_task_node_passes_without_deep_explanation(client):
    nodes = client.post(
        "/api/skills/generate", json={"topic": "我要把一个大象放到冰箱里"}
    ).json()["nodes"]
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
    ).json()["nodes"]
    root = next(n for n in nodes if n["parent_id"] is None)

    start = client.post(f"/api/skills/{root['id']}/audits")
    audit_id = start.json()["session"]["id"]

    hollow_answer = "随便弄弄应该可以吧。"
    client.post(f"/api/audits/{audit_id}/turns", json={"content": hollow_answer})
    verdict = client.post(f"/api/audits/{audit_id}/turns", json={"content": hollow_answer}).json()
    assert verdict["passed"] is False


def test_concept_root_is_asked_about_boundaries_not_content(client):
    """根节点是容器，问"从零讲给我听"没有意义 —— 该问的是适用边界。

    这条守的是最早那个问题：「机器人学基础」这类节点被问"讲讲它是什么"时，
    任何泛泛而谈都像回事，审计得不到任何信号。
    """
    nodes = client.post("/api/skills/generate", json={"topic": "B 树"}).json()["nodes"]
    root = next(n for n in nodes if n["parent_id"] is None)
    assert root["node_type"] == "concept"

    opening = client.post(f"/api/skills/{root['id']}/audits").json()["opening_question"]

    assert "从零开始" not in opening
    assert "该用" in opening and "不该" in opening


def test_concept_leaf_still_gets_the_full_feynman_protocol(client, client_engine):
    """叶子是最具体的单元，仍然走原来那套"从零讲给我听"。"""
    nodes = client.post("/api/skills/generate", json={"topic": "B 树"}).json()["nodes"]
    parents = {n["parent_id"] for n in nodes}
    leaf = next(n for n in nodes if n["id"] not in parents)
    _unlock(client_engine, leaf["id"])

    opening = client.post(f"/api/skills/{leaf['id']}/audits").json()["opening_question"]

    assert "从零开始" in opening


def test_branch_opening_names_its_children(client, client_engine):
    """中间节点的价值在于统摄下面的东西，开场就该问那些东西之间的关系。"""
    nodes = client.post("/api/skills/generate", json={"topic": "B 树"}).json()["nodes"]
    parents = {n["parent_id"] for n in nodes if n["parent_id"] is not None}
    branch = next(n for n in nodes if n["id"] in parents and n["parent_id"] is not None)
    children = [n["title"] for n in nodes if n["parent_id"] == branch["id"]]
    _unlock(client_engine, branch["id"])

    opening = client.post(f"/api/skills/{branch['id']}/audits").json()["opening_question"]

    assert "归在一起" in opening
    assert children[0] in opening
