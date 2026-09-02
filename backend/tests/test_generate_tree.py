"""课程编排（Planner）：分类树 + 先修图。

两组边长在同一批节点上但含义不同，测试要能分开验证：parent_id 是"属于"，
先修边是"学之前要会"。
"""

from sqlmodel import Session, select

from app.models import SkillNode, SkillPrerequisite
from app.services.prerequisites import add_prerequisites


def test_generate_tree_creates_root_and_children(client):
    resp = client.post("/api/skills/generate", json={"topic": "B 树"})
    assert resp.status_code == 200
    nodes = resp.json()["nodes"]
    assert len(nodes) == 4

    root = next(n for n in nodes if n["parent_id"] is None)
    assert root["status"] == "available"
    assert "B 树" in root["title"] or "B" in root["title"]

    children = [n for n in nodes if n["parent_id"] == root["id"]]
    assert len(children) == 2
    assert all(c["status"] == "locked" for c in children)


def test_generate_tree_is_addable_alongside_seed(client):
    before = client.get("/api/skills").json()
    client.post("/api/skills/generate", json={"topic": "并发编程"})
    after = client.get("/api/skills").json()
    assert len(after) == len(before) + 4


def test_generate_tree_slugs_unique_across_batches(client):
    client.post("/api/skills/generate", json={"topic": "同一个主题"})
    client.post("/api/skills/generate", json={"topic": "同一个主题"})
    skills = client.get("/api/skills").json()
    slugs = [s["slug"] for s in skills]
    assert len(slugs) == len(set(slugs))


def test_generated_root_is_immediately_auditable(client):
    nodes = client.post("/api/skills/generate", json={"topic": "图数据库"}).json()["nodes"]
    root = next(n for n in nodes if n["parent_id"] is None)
    resp = client.post(f"/api/skills/{root['id']}/audits")
    assert resp.status_code == 200


def test_generate_tree_records_prerequisites(client):
    body = client.post("/api/skills/generate", json={"topic": "B 树"}).json()

    assert body["prerequisites"]
    edge = body["prerequisites"][0]
    assert edge["skill_id"] != edge["prerequisite_id"]
    assert edge["reason"]


def test_a_prerequisite_can_link_siblings(client):
    """兄弟之间的先修 —— 树结构完全表达不了的那种关系。

    这是先修图存在的理由：两个节点在树上同父平级、彼此无关，学习上却有严格顺序。
    """
    body = client.post("/api/skills/generate", json={"topic": "B 树"}).json()
    by_id = {n["id"]: n for n in body["nodes"]}
    edge = body["prerequisites"][0]

    assert by_id[edge["skill_id"]]["parent_id"] == by_id[edge["prerequisite_id"]]["parent_id"]


def test_course_size_is_configurable(client):
    """node_count / max_depth / difficulty 会传给编排官。

    MockProvider 忽略这些参数（脚本树固定四个节点），所以这里只验证它们被接受、
    不会 422 —— 真实效果要靠真 provider 跑。
    """
    resp = client.post(
        "/api/skills/generate",
        json={"topic": "强化学习", "node_count": 20, "max_depth": 5, "difficulty": "deep"},
    )

    assert resp.status_code == 200


def test_out_of_range_course_parameters_are_rejected(client):
    for bad in ({"node_count": 1}, {"node_count": 500}, {"max_depth": 1}, {"difficulty": "insane"}):
        resp = client.post("/api/skills/generate", json={"topic": "强化学习", **bad})
        assert resp.status_code == 422, bad


def test_cycles_are_dropped_rather_than_stored(client, client_engine):
    """成环的先修边一旦入库，课程就没有合法起点了。"""
    with Session(client_engine) as session:
        a, b = session.exec(select(SkillNode)).all()[:2]
        added = add_prerequisites(session, [(a.id, b.id, "a 要先会 b")])
        assert added == 1
        # 反向边会形成 a -> b -> a，必须被丢弃。
        added_back = add_prerequisites(session, [(b.id, a.id, "b 要先会 a")])
        session.commit()

        assert added_back == 0
        assert len(session.exec(select(SkillPrerequisite)).all()) == 1


def test_duplicate_and_self_edges_are_ignored(client, client_engine):
    with Session(client_engine) as session:
        a, b = session.exec(select(SkillNode)).all()[:2]
        add_prerequisites(session, [(a.id, b.id, "r")])
        session.commit()

        again = add_prerequisites(session, [(a.id, b.id, "r"), (a.id, a.id, "self")])
        session.commit()

        assert again == 0


def test_longer_cycles_are_detected(client, client_engine):
    """三段环 a -> b -> c -> a 也要挡住，不只是直接互指。"""
    with Session(client_engine) as session:
        a, b, c = session.exec(select(SkillNode)).all()[:3]
        add_prerequisites(session, [(a.id, b.id, "r"), (b.id, c.id, "r")])
        session.commit()

        added = add_prerequisites(session, [(c.id, a.id, "r")])
        session.commit()

        assert added == 0


def test_parent_child_edges_are_not_stored_as_prerequisites(client):
    """父子先修边是冗余的 —— 解锁机制已经强制了父子顺序。

    模型即使输出了它们（prompt 明确禁止但仍会发生），也不该占用先修图的空间。
    """
    body = client.post("/api/skills/generate", json={"topic": "B 树"}).json()
    parent_of = {n["id"]: n["parent_id"] for n in body["nodes"]}

    for edge in body["prerequisites"]:
        assert parent_of.get(edge["skill_id"]) != edge["prerequisite_id"]
