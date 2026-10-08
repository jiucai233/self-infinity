"""Courses of any size: the Planner writes a first layer and leaves categories to break down
later (`expand`); POST /skills/{id}/expand breaks one down; a challenge (test_out) on a branch
masters everything under it."""

import json

import pytest
from sqlmodel import Session, select

from app.agents.planner import Planner
from app.models import AuditSession, SkillNode
from app.services import course_generation
from tests.helpers import BrokenProvider, ScriptedProvider, generate, ids_by_slug

LONG = "It works because each step follows from the definition, and the edge cases follow from the same rule. " * 2


def node(slug, title, parents=(), expand=False, description=""):
    return {"slug": slug, "title": title, "description": description or f"{title}.", "parents": list(parents),
            "node_type": "concept", "expand": expand}


# Computer vision, first layer: one chapter broken down, one left for later.
TOP = json.dumps({"nodes": [
    node("cv", "Computer Vision"),
    node("detection", "Object Detection", ["cv"], expand=True, description="Two-stage and one-stage detectors."),
    node("features", "Image Features", ["cv"]),
    node("sift", "SIFT", ["features"]),
    node("hog", "HOG", ["features"]),
], "requires": []})

DETECTION = json.dumps({"nodes": [
    node("two-stage", "Two-Stage Detectors", ["detection"]),
    node("faster-rcnn", "Faster R-CNN", ["two-stage"]),
    node("one-stage", "One-Stage Detectors", ["detection"], expand=True),
    node("sift", "SIFT", ["detection"]),  # already in the course: dropped
], "requires": [{"from": "faster-rcnn", "to": "one-stage", "reason": "Anchors first."}]})


def use_planner(monkeypatch, *outputs):
    provider = ScriptedProvider(planner=list(outputs))
    monkeypatch.setattr("app.routers.skills.get_provider", lambda agent=None: provider)
    return provider


def by_slug(body) -> dict[str, dict]:
    return {n["slug"]: n for n in body["nodes"]}


@pytest.fixture(name="cv")
def cv_fixture(client, monkeypatch):
    provider = use_planner(monkeypatch, TOP, DETECTION)
    body = generate(client, "Computer Vision", search_syllabus=False)
    return provider, body


# ---------------------------------------------------------------- the first layer


def test_a_category_left_for_later_is_saved_unexpanded(cv):
    _, body = cv
    nodes = by_slug(body)

    assert nodes["detection"]["unexpanded"] is True
    assert not any(nodes[s]["unexpanded"] for s in ("cv", "features", "sift", "hog"))


def test_an_unexpanded_chapter_is_its_own_open_node(cv):
    _, body = cv
    nodes = by_slug(body)

    assert {s for s, n in nodes.items() if n["status"] == "available"} == {"detection", "sift"}


def test_expand_true_on_a_node_with_children_is_ignored(client, monkeypatch):
    top = json.dumps({"nodes": [node("r", "Root"), node("a", "A", ["r"], expand=True), node("a1", "A1", ["a"])]})
    use_planner(monkeypatch, top)

    assert not any(n["unexpanded"] for n in generate(client, "X", search_syllabus=False)["nodes"])


# ---------------------------------------------------------------- POST /skills/{id}/expand


def test_expanding_hangs_the_parts_under_the_node(client, cv):
    provider, body = cv
    detection = by_slug(body)["detection"]["id"]

    response = client.post(f"/api/skills/{detection}/expand")

    assert response.status_code == 200
    after = by_slug(response.json())
    assert set(after) == {"cv", "detection", "features", "sift", "hog", "two-stage", "faster-rcnn", "one-stage"}
    assert after["detection"]["unexpanded"] is False and after["one-stage"]["unexpanded"] is True
    contains = {(e["from_id"], e["to_id"]) for e in response.json()["edges"] if e["kind"] == "contains"}
    assert (detection, after["two-stage"]["id"]) in contains and (after["two-stage"]["id"], after["faster-rcnn"]["id"]) in contains
    requires = [e for e in response.json()["edges"] if e["kind"] == "requires"]
    assert [(e["from_id"], e["to_id"], e["reason"]) for e in requires] == [
        (after["faster-rcnn"]["id"], after["one-stage"]["id"], "Anchors first."),
    ]
    # The chapter's open node moves down to its first part.
    assert {s for s, n in after.items() if n["status"] == "available"} == {"faster-rcnn", "sift"}


def test_the_expand_prompt_names_the_node_its_path_and_what_the_course_has(client, cv):
    provider, body = cv
    client.post(f"/api/skills/{by_slug(body)['detection']['id']}/expand")

    messages = provider.calls_for("planner")[1]
    assert "Break down one of its nodes" in messages[0]["content"]
    assert "Budget: at most 40 nodes" in messages[0]["content"]
    user = messages[1]["content"]
    assert user.startswith('Course: Computer Vision\nBreak down: Object Detection (slug "detection")')
    assert "Where it sits: Computer Vision > Object Detection" in user
    assert "- SIFT" in user and "- Object Detection" not in user


def test_a_node_can_only_be_expanded_once(client, cv):
    _, body = cv
    detection = by_slug(body)["detection"]["id"]
    client.post(f"/api/skills/{detection}/expand")

    assert client.post(f"/api/skills/{detection}/expand").status_code == 400
    assert client.post(f"/api/skills/{by_slug(body)['sift']['id']}/expand").status_code == 400
    assert client.post("/api/skills/999/expand").status_code == 404


def test_a_failed_expansion_is_a_502_and_leaves_the_node_to_try_again(client, cv, monkeypatch, client_engine):
    _, body = cv
    detection = by_slug(body)["detection"]["id"]
    monkeypatch.setattr("app.routers.skills.get_provider", lambda agent=None: BrokenProvider())

    assert client.post(f"/api/skills/{detection}/expand").status_code == 502
    with Session(client_engine) as session:
        assert session.get(SkillNode, detection).unexpanded is True
        assert len(session.exec(select(SkillNode)).all()) == 5


def test_parts_that_name_no_parent_hang_under_the_node_and_slugs_never_collide(client, monkeypatch):
    top = json.dumps({"nodes": [node("r", "Root"), node("a", "A", ["r"], expand=True), node("b", "B", ["r"])]})
    parts = json.dumps({"nodes": [node("b", "B Prime"), node("c", "C", ["nowhere"])]})
    use_planner(monkeypatch, top, parts)
    a = by_slug(generate(client, "X", search_syllabus=False))["a"]["id"]

    after = client.post(f"/api/skills/{a}/expand").json()

    parents = {e["to_id"]: e["from_id"] for e in after["edges"] if e["kind"] == "contains"}
    nodes = by_slug(after)
    assert nodes["b-2"]["title"] == "B Prime" and parents[nodes["b-2"]["id"]] == a
    assert parents[nodes["c"]["id"]] == a


def test_a_full_course_is_not_expanded(client, cv, monkeypatch):
    _, body = cv
    monkeypatch.setattr(course_generation, "MAX_COURSE_NODES", 5)

    assert client.post(f"/api/skills/{by_slug(body)['detection']['id']}/expand").status_code == 409


# ---------------------------------------------------------------- audits on an unexpanded node, and challenges


def start(client, skill_id, **body):
    return client.post(f"/api/skills/{skill_id}/audits", json=body)


def test_an_unexpanded_node_is_broken_down_or_challenged_not_audited(client, cv):
    _, body = cv
    detection = by_slug(body)["detection"]["id"]

    assert start(client, detection).status_code == 400
    challenge = start(client, detection, test_out=True)
    assert challenge.status_code == 200
    assert challenge.json()["session"]["test_out"] is True
    assert challenge.json()["opening_question"] == (
        "So you already know “Object Detection”. Prove it: what are its main parts, and how does the most "
        "important one work?"
    )


def test_a_leaf_cannot_be_challenged_and_a_mastered_node_need_not_be(client):
    ids = ids_by_slug(generate(client, "Math"))

    assert start(client, ids["discriminant"], test_out=True).status_code == 400
    from tests.helpers import pass_node

    for slug in ("discriminant", "root-coefficient", "quadratic-equation"):
        pass_node(client, ids[slug])
    assert start(client, ids["quadratic-equation"], test_out=True).status_code == 400


def test_a_locked_branch_can_be_challenged_and_its_parts_are_sampled(client):
    ids = ids_by_slug(generate(client, "Math"))

    started = start(client, ids["algebra"], test_out=True).json()

    # The smallest units under Algebra, nearest first: the leaves under its two sections.
    assert started["opening_question"] == (
        "So you already know “Algebra”. Prove it, one part at a time. Start with “Discriminant”: how does it work?"
    )
    assert started["session"]["node_position"] == "branch"


def test_the_auditor_is_told_it_is_a_challenge_with_the_parts(client, monkeypatch):
    ids = ids_by_slug(generate(client, "Math"))
    provider = ScriptedProvider()
    monkeypatch.setattr("app.routers.audits.get_provider", lambda agent=None: provider)
    audit = start(client, ids["algebra"], test_out=True).json()["session"]["id"]

    client.post(f"/api/audits/{audit}/turns", json={"content": "Sequences are lists with a rule."})

    system = provider.system_prompts("auditor")[0]
    assert "Position: challenge on the whole area" in system
    assert "Parts: Discriminant, Roots and Coefficients, Limits of Sequences" in system
    assert "one part they do not know fails the challenge" in system


def answer(client, audit_id, *answers):
    result = None
    for text in answers:
        result = client.post(f"/api/audits/{audit_id}/turns", json={"content": text}).json()
    return result


def test_passing_a_challenge_masters_everything_under_the_node(client, client_engine):
    ids = ids_by_slug(generate(client, "Math"))
    audit = start(client, ids["algebra"], test_out=True).json()["session"]["id"]

    verdict = answer(client, audit, "First.", LONG)

    assert verdict["type"] == "verdict" and verdict["passed"] is True
    nodes = {n["slug"]: n for n in client.get("/api/skills").json()}
    under = ("quadratic-equation", "discriminant", "root-coefficient", "sequences", "sequence-limit")
    assert all(nodes[s]["status"] == "mastered" and nodes[s]["tested_out"] for s in under)
    assert nodes["algebra"]["status"] == "mastered" and nodes["algebra"]["tested_out"] is False
    assert nodes["algebra"]["mastery_score"] == verdict["score"]
    assert nodes["linear-function"]["status"] == "available"  # another chapter: untouched
    assert client.get("/api/audits").json()[0]["test_out"] is True
    with Session(client_engine) as session:
        assert session.get(AuditSession, audit).max_turns == 8


def test_failing_a_challenge_changes_nothing(client):
    ids = ids_by_slug(generate(client, "Math"))
    before = {n["slug"]: n["status"] for n in client.get("/api/skills").json()}
    audit = start(client, ids["algebra"], test_out=True).json()["session"]["id"]

    verdict = answer(client, audit, "First.", "I don't know.")

    assert verdict["passed"] is False
    assert {n["slug"]: n["status"] for n in client.get("/api/skills").json()} == before


# ---------------------------------------------------------------- the Planner


def test_expand_flags_are_parsed():
    planned = Planner.parse(TOP)

    assert [(n.slug, n.expand) for n in planned.nodes] == [
        ("cv", False), ("detection", True), ("features", False), ("sift", False), ("hog", False),
    ]
    assert Planner.parse(json.dumps({"nodes": [{"title": "A", "expand": "yes"}]})).nodes[0].expand is False


def test_the_mock_vision_course_comes_in_layers(client):
    body = generate(client, "Computer Vision", search_syllabus=False)
    nodes = by_slug(body)

    assert [s for s, n in nodes.items() if n["unexpanded"]] == ["geometry", "recognition"]
    assert sorted(s for s, n in nodes.items() if n["status"] == "available") == ["geometry", "harris", "recognition"]

    after = by_slug(client.post(f"/api/skills/{nodes['geometry']['id']}/expand").json())
    assert [n["title"] for s, n in after.items() if s.startswith("geometry-part")] == [
        "Geometric Vision 1", "Geometric Vision 2", "Geometric Vision 3",
    ]
    assert after["geometry-part-1"]["status"] == "available" and after["geometry"]["status"] == "locked"
