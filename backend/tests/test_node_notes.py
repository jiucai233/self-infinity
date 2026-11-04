"""The player's study notes on a node (contract section 52): no LLM, never given to an agent,
gone with the node."""

from sqlmodel import Session, select

from app.llm.mock import MockProvider
from app.models import NodeNote
from tests.helpers import generate, ids_by_slug, pass_node


def node(client) -> int:
    return ids_by_slug(generate(client))["discriminant"]


def test_a_fresh_node_has_no_notes(client):
    assert client.get(f"/api/skills/{node(client)}/notes").json() == []


def test_add_list_newest_first_edit_and_delete(client):
    skill = node(client)
    first = client.post(f"/api/skills/{skill}/notes", json={"content": "  b² − 4ac decides  "})
    assert first.status_code == 200
    first = first.json()
    assert first["content"] == "b² − 4ac decides"
    assert first["skill_id"] == skill
    assert first["created_at"] == first["updated_at"]
    second = client.post(f"/api/skills/{skill}/notes", json={"content": "two lines\nof note"}).json()

    assert [n["id"] for n in client.get(f"/api/skills/{skill}/notes").json()] == [second["id"], first["id"]]

    edited = client.put(f"/api/notes/{first['id']}", json={"content": "Negative: no real roots"})
    assert edited.status_code == 200
    assert edited.json()["content"] == "Negative: no real roots"
    assert edited.json()["created_at"] == first["created_at"]
    assert edited.json()["updated_at"] >= first["updated_at"]

    assert client.delete(f"/api/notes/{second['id']}").status_code == 204
    assert [n["content"] for n in client.get(f"/api/skills/{skill}/notes").json()] == ["Negative: no real roots"]


def test_empty_or_too_long_is_400(client):
    skill = node(client)
    assert client.post(f"/api/skills/{skill}/notes", json={"content": "   "}).status_code == 400
    assert client.post(f"/api/skills/{skill}/notes", json={"content": "x" * 4001}).status_code == 400
    assert client.post(f"/api/skills/{skill}/notes", json={"content": "x" * 4000}).status_code == 200
    note = client.post(f"/api/skills/{skill}/notes", json={"content": "keep"}).json()
    assert client.put(f"/api/notes/{note['id']}", json={"content": ""}).status_code == 400
    assert client.put(f"/api/notes/{note['id']}", json={"content": "y" * 4001}).status_code == 400
    assert client.get(f"/api/skills/{skill}/notes").json()[0]["content"] == "keep"
    assert client.post(f"/api/skills/{skill}/notes", json={}).status_code == 422


def test_unknown_node_or_note_is_404(client):
    assert client.get("/api/skills/999/notes").status_code == 404
    assert client.post("/api/skills/999/notes", json={"content": "x"}).status_code == 404
    assert client.put("/api/notes/999", json={"content": "x"}).status_code == 404
    assert client.delete("/api/notes/999").status_code == 404


def test_notes_belong_to_their_node(client):
    ids = ids_by_slug(generate(client))
    client.post(f"/api/skills/{ids['discriminant']}/notes", json={"content": "mine"})
    assert client.get(f"/api/skills/{ids['root-coefficient']}/notes").json() == []


def test_the_auditor_never_sees_a_note(client, monkeypatch):
    skill = node(client)
    client.post(f"/api/skills/{skill}/notes", json={"content": "SECRET-NOTE-MARKER"})
    seen: list[str] = []
    complete = MockProvider.complete

    def spy(self, messages):
        seen.extend(m["content"] for m in messages)
        return complete(self, messages)

    monkeypatch.setattr(MockProvider, "complete", spy)
    pass_node(client, skill)

    assert seen
    assert not any("SECRET-NOTE-MARKER" in text for text in seen)


def test_deleting_a_branch_deletes_its_notes(client, client_engine):
    ids = ids_by_slug(generate(client))
    client.post(f"/api/skills/{ids['derivative']}/notes", json={"content": "gone with it"})
    client.post(f"/api/skills/{ids['discriminant']}/notes", json={"content": "stays"})

    assert client.delete(f"/api/skills/{ids['calculus']}").status_code == 200

    with Session(client_engine) as session:
        assert [n.content for n in session.exec(select(NodeNote)).all()] == ["stays"]


def test_deleting_a_course_with_its_nodes_deletes_their_notes(client, client_engine):
    course = generate(client)
    skill = ids_by_slug(course)["discriminant"]
    client.post(f"/api/skills/{skill}/notes", json={"content": "gone"})

    client.delete(f"/api/courses/{course['course']['id']}", params={"delete_nodes": "true"})

    with Session(client_engine) as session:
        assert session.exec(select(NodeNote)).all() == []
