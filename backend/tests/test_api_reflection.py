"""反思接口：Recorder → 保存 → 响应 → Linker（后台）、/principles、/graph（IT-19 ~ IT-21）。"""

import asyncio
import json
from datetime import datetime

from sqlmodel import Session, select

from app.llm.base import agent_of
from app.llm.mock import MockProvider
from app.main import app
from app.models import (
    AuditStatus,
    LinkKind,
    LinkTargetKind,
    Principle,
    PrincipleLink,
    SkillNode,
)
from tests.helpers import (
    BrokenProvider,
    ScriptedProvider,
    fail_node,
    generate,
    ids_by_slug,
    make_audit,
    make_course,
    make_principle,
    make_skill,
    pass_node,
    start,
)

REFLECTION = "I thought no real roots meant no solutions."


def use_provider(monkeypatch, provider, agents=None):
    """Patch the audits router's provider; `agents` limits it to some sub-agents."""
    monkeypatch.setattr(
        "app.routers.audits.get_provider",
        lambda agent=None: provider if agents is None or agent in agents else MockProvider(),
    )


def failed_audit_on_quadratic_equation(client) -> tuple[dict, int]:
    """Pass the root and algebra, then fail Quadratic Equations. Returns (ids by slug, audit id)."""
    ids = ids_by_slug(generate(client, "Math"))
    pass_node(client, ids["high-school-math"])
    pass_node(client, ids["algebra"])
    return ids, fail_node(client, ids["quadratic-equation"])


def post_reflection(client, audit_id: int, reflection: str = REFLECTION):
    return client.post(f"/api/audits/{audit_id}/reflection", json={"reflection": reflection})


def test_it19_a_failed_audit_gets_a_principle_from_the_recorder(client, client_engine):
    ids, audit_id = failed_audit_on_quadratic_equation(client)

    response = post_reflection(client, audit_id)

    assert response.status_code == 200
    body = response.json()
    assert set(body) == {
        "id", "title", "body", "misconception", "source_session_id", "skill_id", "skill_title", "created_at",
    }
    assert body["id"] == 1
    assert body["title"] == "Revisit “Quadratic Equations”"
    assert body["body"] == "When I explain “Quadratic Equations”, I give the reason before the conclusion."
    assert body["misconception"] == REFLECTION
    assert body["source_session_id"] == audit_id
    assert body["skill_id"] == ids["quadratic-equation"]
    assert body["skill_title"] == "Quadratic Equations"
    assert datetime.fromisoformat(body["created_at"]).utcoffset().total_seconds() == 0

    with Session(client_engine) as session:
        (saved,) = session.exec(select(Principle)).all()
        assert (saved.title, saved.misconception, saved.source_session_id) == (body["title"], REFLECTION, audit_id)


def test_it19_the_recorder_fields_respect_the_length_limits(client):
    _ids, audit_id = failed_audit_on_quadratic_equation(client)

    body = post_reflection(client, audit_id, "x" * 200).json()

    assert len(body["title"]) <= 40 and len(body["body"]) <= 120 and len(body["misconception"]) <= 60
    assert body["misconception"] == "x" * 60


def test_it19_the_recorder_sees_the_node_the_gaps_and_the_reflection(client, monkeypatch):
    _ids, audit_id = failed_audit_on_quadratic_equation(client)
    spy = ScriptedProvider()
    use_provider(monkeypatch, spy, agents={"recorder", "linker"})

    post_reflection(client, audit_id)

    (messages,) = spy.calls_for("recorder")
    assert "Node: Quadratic Equations" in messages[0]["content"]
    assert "You stated the definition but not why it works." in messages[0]["content"]
    assert messages[1] == {"role": "user", "content": REFLECTION}


def test_it19_links_are_saved_after_the_principle_is_returned(client, client_engine):
    ids = ids_by_slug(generate(client, "Math"))
    pass_node(client, ids["high-school-math"])
    pass_node(client, ids["algebra"])
    first_audit = fail_node(client, ids["quadratic-equation"])
    post_reflection(client, first_audit, "First misconception")
    second_audit = fail_node(client, ids["sequences"])

    second = post_reflection(client, second_audit, "Second misconception").json()

    # Mock Linker: one related link to the most recent *other* principle.
    with Session(client_engine) as session:
        (saved,) = session.exec(select(PrincipleLink).where(PrincipleLink.principle_id == second["id"])).all()
        assert (saved.target_kind, saved.target_id, saved.kind) == (LinkTargetKind.principle, 1, LinkKind.related)
        assert saved.reason == "Same concept, similar misconception"
    edges = client.get("/api/graph").json()["edges"]
    assert {"source": "principle:2", "target": "principle:1", "kind": "related", "reason": "Same concept, similar misconception"} in edges


def test_it19_the_mock_linker_only_links_principles_never_nodes(client, client_engine):
    _ids, audit_id = failed_audit_on_quadratic_equation(client)

    post_reflection(client, audit_id)

    with Session(client_engine) as session:
        assert session.exec(select(PrincipleLink)).all() == []  # the Mock only links principles


def test_it19_the_response_is_sent_before_the_linker_runs(client_engine, monkeypatch):
    """Recorder -> save -> respond -> Linker, observed at the ASGI level."""
    events: list[str] = []

    class Spy(MockProvider):
        def complete(self, messages):
            events.append(f"llm:{agent_of(messages)}")
            return super().complete(messages)

    with Session(client_engine) as session:
        course = make_course(session)
        node = make_skill(session, course, "node", "Node")
        make_skill(session, course, "other", "Other node")  # gives the Linker a candidate to judge
        audit = make_audit(session, node, AuditStatus.failed, gaps_json='["A missing point"]')
        audit_id = audit.id
    monkeypatch.setattr("app.routers.audits.get_provider", lambda agent=None: Spy())

    async def call() -> bytes:
        body = json.dumps({"reflection": "My thought"}).encode()
        delivered = False
        response_body = b""

        async def receive():
            nonlocal delivered
            if not delivered:
                delivered = True
                return {"type": "http.request", "body": body, "more_body": False}
            await asyncio.Event().wait()  # no disconnect

        async def send(message):
            nonlocal response_body
            if message["type"] == "http.response.body":
                response_body += message.get("body", b"")
                if not message.get("more_body", False):
                    events.append("response-sent")

        scope = {
            "type": "http",
            "asgi": {"version": "3.0"},
            "http_version": "1.1",
            "method": "POST",
            "scheme": "http",
            "path": f"/api/audits/{audit_id}/reflection",
            "raw_path": f"/api/audits/{audit_id}/reflection".encode(),
            "query_string": b"",
            "root_path": "",
            "headers": [(b"content-type", b"application/json"), (b"content-length", str(len(body)).encode())],
            "client": ("test", 1),
            "server": ("test", 80),
            "state": {},
        }
        await app(scope, receive, send)
        return response_body

    response_body = asyncio.run(call())

    assert json.loads(response_body)["misconception"] == "My thought"
    assert events == ["llm:recorder", "response-sent", "llm:linker"]


def test_a_broken_linker_does_not_fail_the_reflection(client, client_engine, monkeypatch):
    ids = ids_by_slug(generate(client, "Math"))
    pass_node(client, ids["high-school-math"])
    pass_node(client, ids["algebra"])
    audit_id = fail_node(client, ids["quadratic-equation"])
    use_provider(monkeypatch, BrokenProvider(), agents={"linker"})

    response = post_reflection(client, audit_id)

    assert response.status_code == 200
    with Session(client_engine) as session:
        assert len(session.exec(select(Principle)).all()) == 1
        assert session.exec(select(PrincipleLink)).all() == []


def test_linker_links_to_a_node_are_saved_with_the_judged_reason(client, client_engine, monkeypatch):
    ids, audit_id = failed_audit_on_quadratic_equation(client)
    # candidate numbering: no other principles, so nodes of the course (minus the origin) in id order
    candidates_in_order = [s for s in ids if s != "quadratic-equation"]
    target = ids["quadratic-function"]
    ref = candidates_in_order.index("quadratic-function")
    judged = json.dumps({"related": [{"ref": ref, "reason": "x-intercepts mean real roots"}], "contradicts": []}, ensure_ascii=False)
    use_provider(monkeypatch, ScriptedProvider(linker=judged), agents={"linker"})

    post_reflection(client, audit_id)

    with Session(client_engine) as session:
        (link,) = session.exec(select(PrincipleLink)).all()
        assert (link.target_kind, link.target_id, link.kind) == (LinkTargetKind.skill, target, LinkKind.related)
        assert link.reason == "x-intercepts mean real roots"


def test_it20_reflection_on_a_passed_session_is_a_400(client):
    ids = ids_by_slug(generate(client, "Math"))
    audit_id = start(client, ids["high-school-math"])
    client.post(f"/api/audits/{audit_id}/turns", json={"content": "x" * 10})
    client.post(f"/api/audits/{audit_id}/turns", json={"content": "x" * 200})

    response = post_reflection(client, audit_id)

    assert response.status_code == 400
    assert response.json() == {"detail": "reflection is only accepted for a failed audit"}


def test_it20_reflection_on_an_active_session_is_a_400(client):
    ids = ids_by_slug(generate(client, "Math"))
    audit_id = start(client, ids["high-school-math"])

    response = post_reflection(client, audit_id)

    assert response.status_code == 400
    assert response.json() == {"detail": "reflection is only accepted for a failed audit"}


def test_a_second_reflection_for_the_same_audit_is_a_400(client, client_engine):
    _ids, audit_id = failed_audit_on_quadratic_equation(client)
    assert post_reflection(client, audit_id).status_code == 200

    again = post_reflection(client, audit_id, "Another thought")

    assert again.status_code == 400
    assert again.json() == {"detail": "reflection already submitted for this audit"}
    with Session(client_engine) as session:
        assert len(session.exec(select(Principle)).all()) == 1


def test_reflection_on_a_missing_session_is_a_404(client):
    response = post_reflection(client, 999)

    assert response.status_code == 404
    assert response.json() == {"detail": "audit session not found"}


def test_a_blank_reflection_is_rejected(client):
    _ids, audit_id = failed_audit_on_quadratic_equation(client)

    for blank in ("", "   "):
        assert post_reflection(client, audit_id, blank).status_code == 422


def test_a_recorder_failure_is_a_502_and_the_user_can_resubmit(client, client_engine, monkeypatch):
    _ids, audit_id = failed_audit_on_quadratic_equation(client)
    use_provider(monkeypatch, BrokenProvider(), agents={"recorder"})

    failed = post_reflection(client, audit_id)

    assert failed.status_code == 502
    assert failed.json() == {"detail": "Principle extraction failed. Please try again."}
    with Session(client_engine) as session:
        assert session.exec(select(Principle)).all() == []

    # The outage is over. (Never monkeypatch.undo() here: it would also undo the autouse fixture
    # that keeps every provider on the Mock, and the retry would reach for a real one.)
    use_provider(monkeypatch, MockProvider(), agents={"recorder"})
    assert post_reflection(client, audit_id).status_code == 200


def test_unusable_recorder_output_is_a_502_too(client, monkeypatch):
    _ids, audit_id = failed_audit_on_quadratic_equation(client)
    use_provider(monkeypatch, ScriptedProvider(recorder='{"title": "Title only"}'), agents={"recorder"})

    assert post_reflection(client, audit_id).status_code == 502


# ---------------------------------------------------------------- GET /principles


def test_principles_are_listed_newest_first_with_their_origin_node(client):
    ids = ids_by_slug(generate(client, "Math"))
    pass_node(client, ids["high-school-math"])
    pass_node(client, ids["algebra"])
    post_reflection(client, fail_node(client, ids["quadratic-equation"]), "First")
    post_reflection(client, fail_node(client, ids["sequences"]), "Second")

    principles = client.get("/api/principles").json()

    assert [(p["id"], p["misconception"], p["skill_title"]) for p in principles] == [
        (2, "Second", "Sequences"),
        (1, "First", "Quadratic Equations"),
    ]
    assert principles[1]["skill_id"] == ids["quadratic-equation"]
    assert set(principles[0]) == {
        "id", "title", "body", "misconception", "source_session_id", "skill_id", "skill_title", "created_at",
    }


# ---------------------------------------------------------------- GET /graph


def test_it21_graph_after_a_reflection_has_the_principle_node_and_its_origin_edge(client):
    ids, audit_id = failed_audit_on_quadratic_equation(client)
    principle = post_reflection(client, audit_id).json()

    graph = client.get("/api/graph").json()

    principle_node = next(n for n in graph["nodes"] if n["kind"] == "principle")
    assert principle_node == {
        "id": f"principle:{principle['id']}",
        "kind": "principle",
        "title": principle["title"],
        "status": None,
        "node_type": None,
        "course_id": None,
    }
    assert {
        "source": f"principle:{principle['id']}",
        "target": f"skill:{ids['quadratic-equation']}",
        "kind": "origin",
        "reason": None,
    } in graph["edges"]


def test_graph_skill_nodes_carry_status_type_and_course(client):
    ids = ids_by_slug(generate(client, "Math"))
    pass_node(client, ids["high-school-math"])

    nodes = {n["id"]: n for n in client.get("/api/graph").json()["nodes"]}

    assert nodes[f"skill:{ids['high-school-math']}"] == {
        "id": f"skill:{ids['high-school-math']}",
        "kind": "skill",
        "title": "High School Math",
        "status": "mastered",
        "node_type": "concept",
        "course_id": 1,
    }
    assert nodes[f"skill:{ids['algebra']}"]["status"] == "available"
    assert nodes[f"skill:{ids['derivative']}"]["status"] == "locked"


def test_graph_draws_related_and_contradicts_links_between_principles_and_nodes(client, client_engine):
    ids = ids_by_slug(generate(client, "Math"))
    with Session(client_engine) as session:
        node = session.get(SkillNode, ids["quadratic-equation"])
        p1 = make_principle(session, node, "Lesson 1")
        p2 = make_principle(session, node, "Lesson 2")
        p3 = make_principle(session, node, "Lesson 3")
        session.add_all(
            [
                PrincipleLink(principle_id=p2.id, target_kind=LinkTargetKind.principle, target_id=p1.id, kind=LinkKind.related, reason="Same thought"),
                PrincipleLink(principle_id=p2.id, target_kind=LinkTargetKind.skill, target_id=ids["quadratic-function"], kind=LinkKind.related, reason="Applies"),
                PrincipleLink(principle_id=p3.id, target_kind=LinkTargetKind.principle, target_id=p1.id, kind=LinkKind.contradicts, reason="Conflicts"),
            ]
        )
        session.commit()
        p1_id, p2_id, p3_id = p1.id, p2.id, p3.id

    edges = client.get("/api/graph").json()["edges"]

    assert {"source": f"principle:{p2_id}", "target": f"principle:{p1_id}", "kind": "related", "reason": "Same thought"} in edges
    assert {"source": f"principle:{p2_id}", "target": f"skill:{ids['quadratic-function']}", "kind": "related", "reason": "Applies"} in edges
    assert {"source": f"principle:{p3_id}", "target": f"principle:{p1_id}", "kind": "contradicts", "reason": "Conflicts"} in edges
    assert {e["kind"] for e in edges} == {"contains", "requires", "origin", "related", "contradicts"}


def test_graph_covers_every_course(client):
    generate(client, "Math")
    generate(client, "History")

    nodes = client.get("/api/graph").json()["nodes"]

    assert {n["course_id"] for n in nodes} == {1, 2}
    assert len(nodes) == 22
