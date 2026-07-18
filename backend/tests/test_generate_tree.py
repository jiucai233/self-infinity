def test_generate_tree_creates_root_and_children(client):
    resp = client.post("/api/skills/generate", json={"topic": "B 树"})
    assert resp.status_code == 200
    nodes = resp.json()
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
    nodes = client.post("/api/skills/generate", json={"topic": "图数据库"}).json()
    root = next(n for n in nodes if n["parent_id"] is None)
    resp = client.post(f"/api/skills/{root['id']}/audits")
    assert resp.status_code == 200
