def _fail_audit_and_reflect(client, skill_id: int, reflection: str) -> int:
    """Runs MockProvider's concept protocol to a failing verdict, then
    submits a reflection. Returns the new principle's id."""
    start = client.post(f"/api/skills/{skill_id}/audits", json={"mode": "day"})
    assert start.status_code == 200
    audit_id = start.json()["session"]["id"]

    body = None
    for _ in range(6):
        result = client.post(f"/api/audits/{audit_id}/turns", json={"content": "不知道"})
        assert result.status_code == 200
        body = result.json()
        if body["type"] != "probe":
            break
    assert body is not None
    assert body["passed"] is False

    reflection_resp = client.post(
        f"/api/audits/{audit_id}/reflection", json={"reflection": reflection}
    )
    assert reflection_resp.status_code == 200
    return reflection_resp.json()["id"]


def test_reflection_auto_links_related_skill_via_librarian(client):
    # MockProvider's Librarian stand-in reuses the same word-overlap
    # heuristic as retrieval.py — mentioning "递归" in the reflection makes
    # it into the principle body (Scribe's mock just echoes the reflection
    # text), which should then score > 0 against the seeded "递归" skill
    # node and get persisted as a "related" PrincipleLink, distinct from the
    # node the audit actually failed on.
    skills = {s["title"]: s for s in client.get("/api/skills").json()}
    root_id = skills["Big-O 记号"]["id"]
    recursion_id = skills["递归"]["id"]

    principle_id = _fail_audit_and_reflect(
        client, root_id, "下次遇到递归相关的问题，我会先画出子问题的分解结构。"
    )

    graph = client.get("/api/graph").json()
    related_edges = [e for e in graph["edges"] if e["kind"] == "related"]
    assert any(
        e["source"] == f"principle-{principle_id}" and e["target"] == f"skill-{recursion_id}"
        for e in related_edges
    )
    # The origin skill (root) must not also show up as a "related" edge —
    # it already has its own "origin" edge and would just be redundant.
    assert not any(
        e["source"] == f"principle-{principle_id}" and e["target"] == f"skill-{root_id}"
        for e in related_edges
    )
    linked = next(e for e in related_edges if e["target"] == f"skill-{recursion_id}")
    assert linked["reason"]


def test_relink_detects_contradiction_between_principles(client):
    skills = {s["title"]: s for s in client.get("/api/skills").json()}
    root_id = skills["Big-O 记号"]["id"]

    # MockProvider's Librarian flags a "principle" candidate as contradicting
    # whenever its body contains the literal marker "刻意矛盾" — this is the
    # deterministic offline stand-in for "the LLM read these as conflicting".
    principle_a_id = _fail_audit_and_reflect(client, root_id, "刻意矛盾：我下次会故意反着做。")
    principle_b_id = _fail_audit_and_reflect(client, root_id, "这是一条正常的反思，没有特殊标记。")

    relink = client.post("/api/graph/relink")
    assert relink.status_code == 200
    data = relink.json()

    assert data["principles_processed"] == 2
    pairs = {frozenset({c["principle_a_id"], c["principle_b_id"]}) for c in data["contradictions"]}
    assert frozenset({principle_a_id, principle_b_id}) in pairs

    # Deduped: the pair should only be reported once even though the
    # Librarian ran once per principle (and could have flagged it from both
    # directions).
    assert len(data["contradictions"]) == len(pairs)

    graph = client.get("/api/graph").json()
    contradicts_edges = [e for e in graph["edges"] if e["kind"] == "contradicts"]
    assert len(contradicts_edges) >= 1
    assert contradicts_edges[0]["reason"]


def test_relink_on_empty_library_is_a_noop(client):
    relink = client.post("/api/graph/relink")
    assert relink.status_code == 200
    data = relink.json()
    assert data == {"principles_processed": 0, "related_links_created": 0, "contradictions": []}
