def test_graph_includes_parent_origin_and_related_edges(client):
    # Seed data already gives us a skill tree (parent edges). Generate a
    # principle by failing an audit, then check the graph endpoint wires it
    # up with a real "origin" edge back to the node it came from.
    skills = client.get("/api/skills").json()
    root = next(s for s in skills if s["parent_id"] is None)

    start = client.post(f"/api/skills/{root['id']}/audits", json={"mode": "day"})
    assert start.status_code == 200
    audit_id = start.json()["session"]["id"]

    # MockProvider's concept protocol takes a few rounds before it forces a
    # verdict; keep answering with a low-effort reply until it does.
    body = None
    for _ in range(6):
        result = client.post(f"/api/audits/{audit_id}/turns", json={"content": "不知道"})
        assert result.status_code == 200
        body = result.json()
        if body["type"] != "probe":
            break
    assert body is not None
    assert body["passed"] is False

    reflection = client.post(
        f"/api/audits/{audit_id}/reflection",
        json={"reflection": "下次先弄清楚基本定义再回答。"},
    )
    assert reflection.status_code == 200
    principle_id = reflection.json()["id"]

    graph = client.get("/api/graph")
    assert graph.status_code == 200
    data = graph.json()

    node_ids = {n["id"] for n in data["nodes"]}
    assert f"skill-{root['id']}" in node_ids
    assert f"principle-{principle_id}" in node_ids

    # At least one skill parent edge exists (seeded tree has depth > 1).
    assert any(e["kind"] == "parent" for e in data["edges"])

    # The principle's real origin edge points back to the node it failed on.
    origin_edges = [e for e in data["edges"] if e["kind"] == "origin"]
    assert {"source": f"principle-{principle_id}", "target": f"skill-{root['id']}", "kind": "origin"} in origin_edges or any(
        e["source"] == f"principle-{principle_id}" and e["target"] == f"skill-{root['id']}"
        for e in origin_edges
    )


def test_graph_empty_state_has_no_principle_nodes(client):
    graph = client.get("/api/graph")
    assert graph.status_code == 200
    data = graph.json()
    assert all(n["kind"] == "skill" for n in data["nodes"])
    assert all(e["kind"] == "parent" for e in data["edges"])


def test_graph_exposes_prerequisite_edges(client, client_engine):
    """先修边和 parent 边并存于同一张图，但是两种 kind。

    它们长在同一批节点上却表达不同的东西：parent 是分类，prerequisite 是顺序。
    前端要能分开画，才谈得上"树负责组织、先修图负责排课"。
    """
    from sqlmodel import Session, select

    from app.models import SkillNode
    from app.services.prerequisites import add_prerequisites

    with Session(client_engine) as session:
        a, b = session.exec(select(SkillNode)).all()[:2]
        add_prerequisites(session, [(a.id, b.id, "先会 b 才能学 a")])
        session.commit()
        a_id, b_id = a.id, b.id

    edges = client.get("/api/graph").json()["edges"]
    prereq = [e for e in edges if e["kind"] == "prerequisite"]

    assert len(prereq) == 1
    # 方向按阅读顺序：从先修指向需要它的那个。
    assert prereq[0]["source"] == f"skill-{b_id}"
    assert prereq[0]["target"] == f"skill-{a_id}"
    assert prereq[0]["reason"] == "先会 b 才能学 a"
    # parent 边不受影响。
    assert any(e["kind"] == "parent" for e in edges)
