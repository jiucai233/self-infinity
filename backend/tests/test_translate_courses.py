"""POST /api/courses/translate: courses follow the app's language (app/services/translation.py)."""

import json

from sqlmodel import Session

from app.models import AuditStatus, Course, SkillNode
from app.routers import courses as courses_router
from app.services import points
from tests.helpers import ScriptedProvider, make_audit, make_course, make_skill


def _english_course(session: Session):
    course = make_course(session, "Linear algebra\n\nQ: Why?\nA: For machine learning")
    root = make_skill(session, course, "root", "Linear algebra", description="Vectors and matrices")
    leaf = make_skill(session, course, "eigen", "Eigenvalues", description="What an eigenvalue is")
    points.set_points(leaf, ["Characteristic polynomial", "Eigenvector"])
    session.add(leaf)
    session.commit()
    return course, root, leaf


def _zh_answer(course, root, leaf) -> str:
    return json.dumps(
        {
            "course": {"title": "线性代数"},
            "nodes": {
                str(root.id): {"title": "线性代数", "description": "向量与矩阵"},
                str(leaf.id): {"title": "特征值", "description": "特征值是什么", "points": ["特征多项式", "特征向量"]},
            },
        },
        ensure_ascii=False,
    )


def _use(monkeypatch, provider):
    monkeypatch.setattr(courses_router, "get_provider", lambda agent=None: provider)


def test_translates_and_stores(client, client_engine, monkeypatch):
    with Session(client_engine) as session:
        course, root, leaf = _english_course(session)
        provider = ScriptedProvider(translator=_zh_answer(course, root, leaf))
        ids = course.id, root.id, leaf.id
    _use(monkeypatch, provider)

    response = client.post("/api/courses/translate", json={"language": "zh"})

    assert response.status_code == 200, response.text
    assert response.json() == {"translated": 1, "skipped": 0}
    assert len(provider.calls_for("translator")) == 1
    sent = json.loads(provider.calls_for("translator")[0][-1]["content"])
    assert sent["course"]["title"] == "Linear algebra"  # the clarification answers are not sent
    assert sent["nodes"][str(ids[2])]["points"] == ["Characteristic polynomial", "Eigenvector"]
    with Session(client_engine) as session:
        course = session.get(Course, ids[0])
        assert course.topic == "线性代数\n\nQ: Why?\nA: For machine learning"
        assert course.language == "zh"
        root = session.get(SkillNode, ids[1])
        assert (root.title, root.description, root.slug) == ("线性代数", "向量与矩阵", "root")
        leaf = session.get(SkillNode, ids[2])
        assert (leaf.title, leaf.description) == ("特征值", "特征值是什么")
        assert [p["title"] for p in leaf.points] == ["特征多项式", "特征向量"]

    # Translating again into the same language asks nothing.
    response = client.post("/api/courses/translate", json={"language": "zh"})
    assert response.json() == {"translated": 0, "skipped": 0}
    assert len(provider.calls_for("translator")) == 1


def test_points_keep_their_results(client, client_engine, monkeypatch):
    with Session(client_engine) as session:
        course, root, leaf = _english_course(session)
        points.record_results(leaf, [{"title": "Eigenvector", "ok": False, "note": "Mixed up"}])
        session.add(leaf)
        session.commit()
        provider = ScriptedProvider(translator=_zh_answer(course, root, leaf))
        leaf_id = leaf.id
    _use(monkeypatch, provider)

    assert client.post("/api/courses/translate", json={"language": "zh"}).json()["translated"] == 1
    with Session(client_engine) as session:
        assert session.get(SkillNode, leaf_id).points == [
            {"title": "特征多项式", "ok": None, "note": None},
            {"title": "特征向量", "ok": False, "note": "Mixed up"},
        ]


def _assert_untouched(client_engine, ids):
    with Session(client_engine) as session:
        course = session.get(Course, ids[0])
        assert course.topic.startswith("Linear algebra")
        assert course.language is None
        assert session.get(SkillNode, ids[1]).title == "Linear algebra"
        leaf = session.get(SkillNode, ids[2])
        assert leaf.title == "Eigenvalues"
        assert [p["title"] for p in leaf.points] == ["Characteristic polynomial", "Eigenvector"]


def test_invalid_json_leaves_the_course_untouched(client, client_engine, monkeypatch):
    with Session(client_engine) as session:
        course, root, leaf = _english_course(session)
        ids = course.id, root.id, leaf.id
    _use(monkeypatch, ScriptedProvider(translator="not json at all"))

    response = client.post("/api/courses/translate", json={"language": "ko"})

    assert response.json() == {"translated": 0, "skipped": 1}
    _assert_untouched(client_engine, ids)


def test_incomplete_json_leaves_the_course_untouched(client, client_engine, monkeypatch):
    with Session(client_engine) as session:
        course, root, leaf = _english_course(session)
        ids = course.id, root.id, leaf.id
        full = json.loads(_zh_answer(course, root, leaf))
    missing_node = {**full, "nodes": {str(ids[1]): full["nodes"][str(ids[1])]}}
    short_points = json.loads(json.dumps(full))
    short_points["nodes"][str(ids[2])]["points"] = ["特征多项式"]
    empty_title = json.loads(json.dumps(full))
    empty_title["nodes"][str(ids[1])]["title"] = "  "

    for answer in (missing_node, short_points, empty_title):
        _use(monkeypatch, ScriptedProvider(translator=json.dumps(answer, ensure_ascii=False)))
        response = client.post("/api/courses/translate", json={"language": "zh"})
        assert response.json() == {"translated": 0, "skipped": 1}, answer
        _assert_untouched(client_engine, ids)


def test_a_course_already_in_the_language_makes_no_call(client, client_engine, monkeypatch):
    with Session(client_engine) as session:
        english, *_ = _english_course(session)
        tagged = make_course(session, "机器学习")
        tagged.language = "zh"
        session.add(tagged)
        session.commit()
        english_id = english.id
    provider = ScriptedProvider(translator="{}")
    _use(monkeypatch, provider)

    # Into English: the untranslated English course is recognised by its text, the Chinese one is
    # translated (and fails here: "{}" is incomplete).
    response = client.post("/api/courses/translate", json={"language": "en"})

    assert response.json() == {"translated": 0, "skipped": 1}
    sent = [json.loads(m[-1]["content"])["course"]["title"] for m in provider.calls_for("translator")]
    assert sent == ["机器学习"]
    with Session(client_engine) as session:
        assert session.get(Course, english_id).language == "en"


def test_points_of_a_node_being_audited_are_not_sent(client, client_engine, monkeypatch):
    with Session(client_engine) as session:
        course, root, leaf = _english_course(session)
        make_audit(session, leaf, status=AuditStatus.active)
        answer = json.loads(_zh_answer(course, root, leaf))
        del answer["nodes"][str(leaf.id)]["points"]
        provider = ScriptedProvider(translator=json.dumps(answer, ensure_ascii=False))
        leaf_id = leaf.id
    _use(monkeypatch, provider)

    assert client.post("/api/courses/translate", json={"language": "zh"}).json()["translated"] == 1
    sent = json.loads(provider.calls_for("translator")[0][-1]["content"])
    assert "points" not in sent["nodes"][str(leaf_id)]
    with Session(client_engine) as session:
        leaf = session.get(SkillNode, leaf_id)
        assert leaf.title == "特征值"
        assert [p["title"] for p in leaf.points] == ["Characteristic polynomial", "Eigenvector"]


def test_rejects_an_unknown_language(client):
    assert client.post("/api/courses/translate", json={"language": "fr"}).status_code == 422


def test_the_mock_answers_the_course_back(client, client_engine):
    with Session(client_engine) as session:
        _english_course(session)
    assert client.post("/api/courses/translate", json={"language": "ko"}).json() == {"translated": 1, "skipped": 0}
