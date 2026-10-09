"""Editing a course by hand (contract #41-#45): rename, add a part, delete a branch, a course
inside a course, and a syllabus applied to a course that exists."""

import json

from sqlmodel import Session, select

from app.models import AuditSession, SkillEdge, SkillNode
from app.routers import skills
from tests.helpers import FIRST, LONG, ScriptedProvider, answer_turns, generate, ids_by_slug, pass_node


def by_slug(body) -> dict[str, dict]:
    return {n["slug"]: n for n in body["nodes"]}


def contains(body) -> set[tuple[int, int, bool]]:
    return {(e["from_id"], e["to_id"], e["is_primary"]) for e in body["edges"] if e["kind"] == "contains"}


def node(slug, title, parents=(), expand=False):
    return {"slug": slug, "title": title, "description": f"{title}.", "parents": list(parents),
            "node_type": "concept", "expand": expand}


def scripted_course(client, monkeypatch, *nodes) -> dict:
    provider = ScriptedProvider(planner=json.dumps({"nodes": list(nodes), "requires": []}))
    original = skills.get_provider
    monkeypatch.setattr(skills, "get_provider", lambda agent=None: provider)
    body = generate(client, nodes[0]["title"], search_syllabus=False)
    monkeypatch.setattr(skills, "get_provider", original)
    return body


# ---------------------------------------------------------------- #41 rename


def test_a_node_is_renamed_and_its_description_rewritten(client):
    ids = ids_by_slug(generate(client))

    body = client.patch(f"/api/skills/{ids['algebra']}", json={"title": "  Algebra   Basics ", "description": "Rings."})

    assert (by_slug(body.json())["algebra"]["title"], by_slug(body.json())["algebra"]["description"]) == (
        "Algebra Basics", "Rings.",
    )
    assert client.patch(f"/api/skills/{ids['algebra']}", json={"title": " "}).status_code == 422
    assert client.patch(f"/api/skills/{ids['algebra']}", json={"title": "x" * 49}).status_code == 422
    assert client.patch("/api/skills/999", json={"title": "A"}).status_code == 404


# ---------------------------------------------------------------- #43 add a part


def test_a_part_is_added_under_a_node(client):
    ids = ids_by_slug(generate(client))

    body = client.post(f"/api/skills/{ids['functions']}/children", json={"title": "Exponential Functions"}).json()

    added = by_slug(body)["exponential-functions"]
    assert (added["title"], added["description"], added["status"]) == ("Exponential Functions", "", "locked")
    assert (ids["functions"], added["id"], True) in contains(body)


def test_a_node_left_for_later_with_a_part_added_still_waits_for_the_rest(client, monkeypatch):
    vision = by_slug(generate(client, "Computer Vision", search_syllabus=False))

    body = client.post(f"/api/skills/{vision['geometry']['id']}/children", json={"title": "Homography"}).json()

    after = by_slug(body)
    assert after["geometry"]["unexpanded"] is True
    # The new part is the chapter's open node now: it comes before what contains it.
    assert after["homography"]["status"] == "available"
    # A second part with the same title gets its own slug.
    again = client.post(f"/api/skills/{vision['geometry']['id']}/children", json={"title": "Homography"}).json()
    assert "homography-2" in by_slug(again)
    # Breaking it down now fills it in: the Planner is told the parts it has.
    provider = ScriptedProvider()
    monkeypatch.setattr(skills, "get_provider", lambda agent=None: provider)
    filled = by_slug(client.post(f"/api/skills/{vision['geometry']['id']}/expand").json())
    assert "Its parts so far (output only what is missing):\n- Homography\n- Homography" in (
        provider.calls_for("planner")[0][1]["content"]
    )
    assert filled["geometry"]["unexpanded"] is False and "geometry-more" in filled


# ---------------------------------------------------------------- #42 delete


def test_deleting_a_branch_deletes_what_is_only_under_it_with_its_history(client, client_engine):
    ids = ids_by_slug(generate(client))
    pass_node(client, ids["sequence-limit"])
    pass_node(client, ids["derivative"])

    body = client.delete(f"/api/skills/{ids['calculus']}").json()

    after = by_slug(body)
    assert "calculus" not in after and "derivative" not in after
    # Limits of Sequences also sits under Sequences: it stays, Sequences is its main parent now.
    assert (ids["sequences"], ids["sequence-limit"], True) in contains(body)
    with Session(client_engine) as session:
        assert session.exec(select(AuditSession).where(AuditSession.skill_id == ids["derivative"])).all() == []
        assert session.exec(select(SkillEdge).where(SkillEdge.to_id == ids["derivative"])).all() == []


def test_the_root_is_the_course_and_is_not_deleted_here(client):
    ids = ids_by_slug(generate(client))

    response = client.delete(f"/api/skills/{ids['high-school-math']}")

    assert response.status_code == 400
    assert response.json()["detail"] == "This is the course itself: delete the course instead."


# ---------------------------------------------------------------- #44 a course inside a course


def test_a_node_becomes_another_course(client, monkeypatch):
    vision = generate(client, "Computer Vision", search_syllabus=False)
    cs = ids_by_slug(scripted_course(client, monkeypatch, node("cs", "Computer Science"), node("ai", "AI", ["cs"]),
                                     node("perception", "Perception", ["ai"], expand=True)))

    body = client.put(f"/api/skills/{cs['perception']}/link", json={"course_id": vision["course"]["id"]}).json()

    perception = by_slug(body)["perception"]
    assert (perception["linked_course_id"], perception["unexpanded"]) == (vision["course"]["id"], False)
    # Its parts are that course: it is not broken down or audited itself.
    assert client.post(f"/api/skills/{cs['perception']}/expand").status_code == 400
    assert client.post(f"/api/skills/{cs['perception']}/audits", json={}).status_code == 400
    # Unlinked, it is a plain node again.
    body = client.put(f"/api/skills/{cs['perception']}/link", json={"course_id": None}).json()
    assert by_slug(body)["perception"]["linked_course_id"] is None


def test_links_that_make_no_sense_are_refused(client, monkeypatch):
    math = generate(client)
    vision = generate(client, "Computer Vision", search_syllabus=False)
    m, v = ids_by_slug(math), ids_by_slug(vision)

    def link(node_id, course_id):
        return client.put(f"/api/skills/{node_id}/link", json={"course_id": course_id})

    assert link(m["discriminant"], math["course"]["id"]).json()["detail"] == "A course cannot be inside itself."
    assert link(m["algebra"], vision["course"]["id"]).status_code == 400  # it has parts
    assert link(m["high-school-math"], vision["course"]["id"]).status_code == 400  # a root
    assert link(m["discriminant"], 999).status_code == 400
    assert link(v["harris"], math["course"]["id"]).status_code == 200
    # Vision holds Math now, so Math cannot hold Vision.
    assert link(m["discriminant"], vision["course"]["id"]).json()["detail"] == (
        "That course already holds this one: the two would contain each other."
    )


def test_a_course_is_found_inside_another_by_title_both_ways(client, monkeypatch):
    # The CS course comes first: its leaf becomes the vision course once that is built.
    scripted_course(client, monkeypatch, node("cs", "Computer Science"),
                    node("cv", "Computer vision", ["cs"]), node("os", "Operating Systems", ["cs"]))
    vision = generate(client, "Computer Vision", search_syllabus=False)
    # And a course built later that has a node titled like an existing course links it at once.
    robots = scripted_course(client, monkeypatch, node("robots", "Robotics"),
                             node("percept", "Computer Vision (Perception)", ["robots"], expand=True))

    maps = {c["course"]["id"]: c for c in [client.get(f"/api/courses/{i}/map").json() for i in (1, 3)]}
    assert by_slug(maps[1])["cv"]["linked_course_id"] == vision["course"]["id"]
    assert by_slug(robots)["percept"]["linked_course_id"] == vision["course"]["id"]
    assert by_slug(robots)["percept"]["unexpanded"] is False
    assert by_slug(maps[1])["os"]["linked_course_id"] is None


def test_mastering_a_course_masters_the_node_that_is_it_and_the_other_way(client, monkeypatch, client_engine):
    vision = generate(client, "Computer Vision", search_syllabus=False)
    v = ids_by_slug(vision)
    cs = ids_by_slug(scripted_course(client, monkeypatch, node("cs", "Computer Science"),
                                     node("ai", "AI", ["cs"]), node("cv", "Computer Vision", ["ai"]),
                                     node("search", "Search", ["ai"])))
    # A challenge on the whole vision course: the CS node that is it is mastered too.
    audit = client.post(f"/api/skills/{v['computer-vision']}/audits", json={"test_out": True}).json()["session"]["id"]
    answer_turns(client, audit, FIRST, LONG)
    assert by_slug(client.get("/api/courses/2/map").json())["cv"]["status"] == "mastered"

    # Unlink, reset, and go the other way: a challenge on CS's AI masters the vision course.
    with Session(client_engine) as session:
        for n in session.exec(select(SkillNode)).all():
            n.status, n.tested_out = "locked", None
            session.add(n)
        session.commit()
    audit = client.post(f"/api/skills/{cs['ai']}/audits", json={"test_out": True}).json()["session"]["id"]
    answer_turns(client, audit, FIRST, LONG)
    after = by_slug(client.get(f"/api/courses/{vision['course']['id']}/map").json())
    assert all(n["status"] == "mastered" for n in after.values())
    assert after["harris"]["tested_out"] is True


def test_deleting_a_course_unlinks_the_nodes_that_were_it(client, monkeypatch):
    vision = generate(client, "Computer Vision", search_syllabus=False)
    scripted_course(client, monkeypatch, node("cs", "Computer Science"), node("cv", "Computer Vision", ["cs"]))

    client.delete(f"/api/courses/{vision['course']['id']}")

    assert by_slug(client.get("/api/courses/2/map").json())["cv"]["linked_course_id"] is None


# ---------------------------------------------------------------- #45 a syllabus applied to a course


def test_an_uploaded_syllabus_adds_what_the_course_lacks(client, monkeypatch):
    ids = ids_by_slug(generate(client))
    pass_node(client, ids["discriminant"])
    provider = ScriptedProvider()
    monkeypatch.setattr("app.routers.courses.get_provider", lambda agent=None: provider)
    upload = client.post(
        "/api/uploads", files={"file": ("syllabus.txt", b"1. Algebra\n2. Matrices\n3. Probability", "text/plain")}
    ).json()

    body = client.post("/api/courses/1/syllabus", json={"upload_ids": [upload["id"]]}).json()

    system, user = provider.calls_for("planner")[0][0]["content"], provider.calls_for("planner")[0][1]["content"]
    assert "Output only new nodes." in system
    assert "Reference document (syllabus.txt)" in system
    assert user.startswith("Course: Math\nTree:\nhigh-school-math: High School Math\n  algebra: Algebra\n")
    after = by_slug(body)
    # Progress stays; nothing is removed.
    assert after["discriminant"]["status"] == "mastered"
    assert set(by_slug(body)) >= set(ids)
    assert body["course"]["source_course"] == "syllabus.txt"


def test_a_syllabus_that_adds_nothing_changes_nothing(client, monkeypatch):
    generate(client)
    before = client.get("/api/courses/1/map").json()
    monkeypatch.setattr("app.routers.courses.get_provider", lambda agent=None: ScriptedProvider(planner='{"nodes": []}'))
    upload = client.post("/api/uploads", files={"file": ("s.txt", b"Algebra", "text/plain")}).json()

    body = client.post("/api/courses/1/syllabus", json={"upload_ids": [upload["id"]]}).json()

    assert set(by_slug(body)) == set(by_slug(before))
    assert contains(body) == contains(before)


def test_no_syllabus_found_is_a_404_and_unknown_things_too(client, monkeypatch):
    generate(client)
    monkeypatch.setattr("app.routers.courses.course_generation.find_syllabus", lambda *a: None)

    assert client.post("/api/courses/1/syllabus", json={}).status_code == 404
    assert client.post("/api/courses/1/syllabus", json={"upload_ids": [99]}).status_code == 404
    assert client.post("/api/courses/9/syllabus", json={}).status_code == 404
