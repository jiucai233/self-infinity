"""Deleting a course (contract endpoint 33): keeping its nodes hides them, deleting them removes
everything the course produced. Either way it leaves its main quest and the study plan."""

import json

from sqlmodel import Session, select

from app.models import (
    AuditSession,
    AuditTurn,
    Course,
    LinkKind,
    LinkTargetKind,
    Principle,
    PrincipleLink,
    SkillEdge,
    SkillNode,
    StudyPlan,
)
from tests.helpers import generate, ids_by_slug, make_principle, pass_node


def setup(client, client_engine):
    """A course under a quest with one node passed and one lesson card on it, and a second
    course whose lesson links to a node of the first."""
    course = generate(client, "Math")
    other = generate(client, "Physics")
    goal = client.post("/api/goals", json={"title": "Pass the exam"}).json()
    client.put(f"/api/goals/{goal['id']}", json={"course_ids": [course["course"]["id"], other["course"]["id"]]})
    root = ids_by_slug(course)["discriminant"]
    pass_node(client, root)
    with Session(client_engine) as session:
        lesson = make_principle(session, session.get(SkillNode, root), title="Own lesson")
        foreign = make_principle(session, session.get(SkillNode, other["nodes"][0]["id"]), title="Other lesson")
        session.add(
            PrincipleLink(principle_id=foreign.id, target_kind=LinkTargetKind.skill, target_id=root, kind=LinkKind.related)
        )
        session.add(
            PrincipleLink(
                principle_id=foreign.id, target_kind=LinkTargetKind.principle, target_id=lesson.id, kind=LinkKind.related
            )
        )
        session.add(
            StudyPlan(
                steps_json=json.dumps(
                    [{"skill_id": root, "course_id": course["course"]["id"]}, {"skill_id": 0, "course_id": 999}]
                ),
                context_json="{}",
            )
        )
        session.commit()
    return course, other, goal


def test_keeping_the_nodes_hides_the_course_and_keeps_its_history(client, client_engine):
    course, other, goal = setup(client, client_engine)
    course_id = course["course"]["id"]
    nodes = set(ids_by_slug(course).values())

    assert client.delete(f"/api/courses/{course_id}").status_code == 204

    assert [c["id"] for c in client.get("/api/courses").json()] == [other["course"]["id"]]
    assert client.get(f"/api/courses/{course_id}/map").status_code == 404
    assert not nodes & {s["id"] for s in client.get("/api/skills").json()}
    graph = client.get("/api/graph").json()
    assert not {f"skill:{n}" for n in nodes} & {n["id"] for n in graph["nodes"]}
    assert all(e["target"] not in {f"skill:{n}" for n in nodes} for e in graph["edges"])
    assert client.get(f"/api/goals").json()[0]["course_ids"] == [other["course"]["id"]]
    # The lesson cards and the audit history stay.
    assert {"Own lesson", "Other lesson"} <= {p["title"] for p in client.get("/api/principles").json()}
    assert client.get("/api/audits").json()
    with Session(client_engine) as session:
        assert session.get(Course, course_id).archived_at is not None
        assert len(session.exec(select(SkillNode).where(SkillNode.course_id == course_id)).all()) == len(nodes)
        (plan,) = session.exec(select(StudyPlan)).all()
        assert [s["course_id"] for s in json.loads(plan.steps_json)] == [999]

    # Gone is gone: a second delete, or putting it under a quest, is a 404.
    assert client.delete(f"/api/courses/{course_id}").status_code == 404
    assert client.put(f"/api/goals/{goal['id']}", json={"course_ids": [course_id]}).status_code == 404


def test_deleting_the_nodes_removes_everything_the_course_made(client, client_engine):
    course, other, _goal = setup(client, client_engine)
    course_id = course["course"]["id"]
    nodes = set(ids_by_slug(course).values())

    assert client.delete(f"/api/courses/{course_id}", params={"delete_nodes": "true"}).status_code == 204

    with Session(client_engine) as session:
        assert session.get(Course, course_id) is None
        assert not session.exec(select(SkillNode).where(SkillNode.course_id == course_id)).all()
        assert all(e.from_id not in nodes and e.to_id not in nodes for e in session.exec(select(SkillEdge)).all())
        # Only the other course's audit (behind its lesson) is left; the passed audit's turns went.
        assert [a.skill_id for a in session.exec(select(AuditSession)).all()] == [other["nodes"][0]["id"]]
        assert not session.exec(select(AuditTurn)).all()
        assert [p.title for p in session.exec(select(Principle)).all()] == ["Other lesson"]
        # The other course's lesson keeps nothing pointing at what is gone.
        assert not session.exec(select(PrincipleLink)).all()
    assert [c["id"] for c in client.get("/api/courses").json()] == [other["course"]["id"]]
    assert client.get("/api/graph").status_code == 200


def test_an_unknown_course_is_404(client):
    assert client.delete("/api/courses/42").status_code == 404
