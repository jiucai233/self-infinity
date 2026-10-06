"""Linker 的编排：挑候选、保存链接、失败只意味着没有链接。"""

import json
from datetime import timedelta

import pytest
from sqlmodel import Session, SQLModel, create_engine, select
from sqlmodel.pool import StaticPool

from app.models import LinkKind, LinkTargetKind, Principle, PrincipleLink, utcnow
from app.services.linking import MAX_CANDIDATES, build_candidates, link_principle, run_linker
from tests.helpers import BrokenProvider, ScriptedProvider, make_course, make_principle, make_skill


@pytest.fixture(name="engine")
def engine_fixture():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    SQLModel.metadata.create_all(engine)
    return engine


@pytest.fixture(name="session")
def session_fixture(engine):
    with Session(engine) as session:
        yield session


def age(session: Session, principle: Principle, minutes: int) -> Principle:
    principle.created_at = utcnow() - timedelta(minutes=minutes)
    session.add(principle)
    session.commit()
    return principle


def test_candidates_are_the_other_lessons_then_the_other_nodes_of_the_same_course(session):
    course = make_course(session)
    origin = make_skill(session, course, "origin", "Origin node")
    other = make_skill(session, course, "other", "Other node")
    older = age(session, make_principle(session, other, "Old lesson"), 30)
    newer = age(session, make_principle(session, other, "Recent lesson"), 10)
    new = make_principle(session, origin, "New lesson")

    candidates = build_candidates(session, new)

    assert [(c.kind, c.id, c.title) for c in candidates] == [
        ("principle", newer.id, "Recent lesson"),  # most recent first
        ("principle", older.id, "Old lesson"),
        ("skill", other.id, "Other node"),  # the origin node is left out: the origin edge already covers it
    ]
    assert candidates[0].text == newer.body
    assert candidates[2].text == "Description"


def test_other_courses_are_not_candidates(session):
    mine = make_course(session, "My course")
    theirs = make_course(session, "Their course")
    origin = make_skill(session, mine, "origin")
    far = make_skill(session, theirs, "far")
    make_principle(session, far, "Their lesson")
    new = make_principle(session, origin, "New lesson")

    assert build_candidates(session, new) == []


def test_there_are_at_most_thirty_candidates_and_nodes_always_get_room(session):
    course = make_course(session)
    origin = make_skill(session, course, "origin")
    nodes = [make_skill(session, course, f"n{i}") for i in range(40)]
    for i in range(14):
        age(session, make_principle(session, nodes[i], f"Lesson {i}"), 100 - i)
    new = make_principle(session, origin, "New lesson")

    candidates = build_candidates(session, new)

    assert len(candidates) == MAX_CANDIDATES == 30
    kinds = [c.kind for c in candidates]
    assert kinds.count("principle") == 10 and kinds.count("skill") == 20
    assert kinds == ["principle"] * 10 + ["skill"] * 20  # lessons first
    assert [c.title for c in candidates if c.kind == "principle"][0] == "Lesson 13"  # the most recent


def test_the_new_lesson_is_never_its_own_candidate(session):
    course = make_course(session)
    origin = make_skill(session, course, "origin")
    new = make_principle(session, origin, "New lesson")

    assert build_candidates(session, new) == []


def test_links_are_saved_with_their_kinds_and_target_kinds(session):
    course = make_course(session)
    origin = make_skill(session, course, "origin")
    target = make_skill(session, course, "target")
    old = make_principle(session, target, "Older lesson")
    new = make_principle(session, origin, "New lesson")
    # candidates: [0] the old lesson, [1] the target node
    judged = json.dumps(
        {
            "related": [{"ref": 0, "reason": "Same thought"}, {"ref": 1, "reason": "Applies"}],
            "contradicts": [{"ref": 0, "reason": "Conflicts"}, {"ref": 1, "reason": "A node cannot contradict"}],
        },
        ensure_ascii=False,
    )

    saved = link_principle(session, ScriptedProvider(linker=judged), new)

    links = session.exec(select(PrincipleLink).order_by(PrincipleLink.id)).all()
    assert saved == 3
    assert [(l.target_kind, l.target_id, l.kind, l.reason) for l in links] == [
        (LinkTargetKind.principle, old.id, LinkKind.related, "Same thought"),
        (LinkTargetKind.skill, target.id, LinkKind.related, "Applies"),
        (LinkTargetKind.principle, old.id, LinkKind.contradicts, "Conflicts"),
    ]
    assert all(l.principle_id == new.id for l in links)


def test_no_candidates_means_no_llm_call_and_no_links(session):
    course = make_course(session)
    new = make_principle(session, make_skill(session, course, "only"), "New lesson")
    provider = ScriptedProvider(linker="{}")

    assert link_principle(session, provider, new) == 0
    assert provider.calls == []


def test_run_linker_opens_its_own_session_and_saves_the_links(engine):
    with Session(engine) as session:
        course = make_course(session)
        origin = make_skill(session, course, "origin")
        make_principle(session, make_skill(session, course, "other"), "Older lesson")
        new_id = make_principle(session, origin, "New lesson").id

    run_linker(engine, lambda: ScriptedProvider(), new_id)  # the Mock links the most recent other lesson

    with Session(engine) as session:
        (link,) = session.exec(select(PrincipleLink)).all()
        assert (link.principle_id, link.kind, link.target_kind) == (new_id, LinkKind.related, LinkTargetKind.principle)


@pytest.mark.parametrize("failure", ["provider", "factory", "missing"])
def test_run_linker_never_raises(engine, failure):
    with Session(engine) as session:
        course = make_course(session)
        new_id = make_principle(session, make_skill(session, course, "origin"), "New lesson").id
        make_skill(session, course, "other")  # gives the Linker something to judge

    def broken_factory():
        raise RuntimeError("cannot build the provider")

    factory = {"provider": lambda: BrokenProvider(), "factory": broken_factory, "missing": lambda: ScriptedProvider()}[failure]
    principle_id = 999 if failure == "missing" else new_id

    run_linker(engine, factory, principle_id)  # must not raise

    with Session(engine) as session:
        assert session.exec(select(PrincipleLink)).all() == []
        assert session.get(Principle, new_id) is not None  # the lesson itself is untouched
