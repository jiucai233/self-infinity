"""Memory Retriever：审计前挑出最多 3 条相关的旧教训（UT-46）。

选择规则：来源节点是这个节点或它的直接邻居（contains / requires，不分方向）的教训，加上
Linker 链接到这个节点的教训；最近的在前。
"""

from datetime import timedelta

import pytest
from sqlmodel import Session, SQLModel, create_engine
from sqlmodel.pool import StaticPool

from app.agents.memory_retriever import recent_misconceptions, retrieve_lessons
from app.models import EdgeKind, LinkKind, LinkTargetKind, Principle, PrincipleLink, utcnow
from tests.helpers import link, make_course, make_principle, make_skill


@pytest.fixture(name="session")
def session_fixture():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    SQLModel.metadata.create_all(engine)
    with Session(engine) as session:
        yield session


def age(session: Session, principle: Principle, minutes: int) -> Principle:
    principle.created_at = utcnow() - timedelta(minutes=minutes)
    session.add(principle)
    session.commit()
    return principle


def titles(lessons) -> list[str]:
    return [p.title for p in lessons]


def test_ut46_a_principle_from_a_requires_neighbour_is_returned(session):
    course = make_course(session)
    equation = make_skill(session, course, "equation", "Quadratic Equations")
    function = make_skill(session, course, "function", "Quadratic Functions")
    link(session, equation, function, EdgeKind.requires)  # Quadratic Equations is learned before Quadratic Functions
    make_principle(session, equation, "State the domain")

    assert titles(retrieve_lessons(session, function)) == ["State the domain"]
    # The neighbour relation is symmetric: the lesson also surfaces going the other way.
    make_principle(session, function, "Graphs and x-intercepts")
    assert set(titles(retrieve_lessons(session, equation))) == {"State the domain", "Graphs and x-intercepts"}


def test_the_node_itself_counts(session):
    course = make_course(session)
    node = make_skill(session, course, "node")
    make_principle(session, node, "Own lesson")

    assert titles(retrieve_lessons(session, node)) == ["Own lesson"]


def test_contains_neighbours_count_in_both_directions(session):
    course = make_course(session)
    parent = make_skill(session, course, "parent")
    child = make_skill(session, course, "child")
    link(session, parent, child, EdgeKind.contains)
    age(session, make_principle(session, parent, "Parent lesson"), 20)
    age(session, make_principle(session, child, "Child lesson"), 10)

    assert titles(retrieve_lessons(session, child)) == ["Child lesson", "Parent lesson"]
    assert titles(retrieve_lessons(session, parent)) == ["Child lesson", "Parent lesson"]


def test_a_principle_from_an_unrelated_node_is_not_returned(session):
    course = make_course(session)
    me = make_skill(session, course, "me")
    far = make_skill(session, course, "far")
    make_principle(session, far, "Far lesson")

    assert retrieve_lessons(session, me) == []


def test_only_direct_neighbours_count_not_neighbours_of_neighbours(session):
    course = make_course(session)
    a = make_skill(session, course, "a")
    b = make_skill(session, course, "b")
    c = make_skill(session, course, "c")
    link(session, a, b, EdgeKind.contains)
    link(session, b, c, EdgeKind.contains)
    make_principle(session, a, "Grandparent lesson")

    assert retrieve_lessons(session, c) == []
    assert titles(retrieve_lessons(session, b)) == ["Grandparent lesson"]


def test_a_principle_the_linker_linked_to_this_node_is_returned(session):
    course = make_course(session)
    origin = make_skill(session, course, "origin")
    target = make_skill(session, course, "target")  # no edge to origin at all
    lesson = make_principle(session, origin, "Linked lesson")
    session.add(
        PrincipleLink(principle_id=lesson.id, target_kind=LinkTargetKind.skill, target_id=target.id, kind=LinkKind.related, reason="Applies")
    )
    session.commit()

    assert titles(retrieve_lessons(session, target)) == ["Linked lesson"]


def test_a_link_to_a_principle_or_to_another_node_does_not_count(session):
    course = make_course(session)
    origin = make_skill(session, course, "origin")
    other = make_skill(session, course, "other")
    me = make_skill(session, course, "me")
    first = make_principle(session, origin, "First lesson")
    second = make_principle(session, origin, "Second lesson")
    session.add(PrincipleLink(principle_id=second.id, target_kind=LinkTargetKind.principle, target_id=first.id, kind=LinkKind.related, reason="r"))
    session.add(PrincipleLink(principle_id=second.id, target_kind=LinkTargetKind.skill, target_id=other.id, kind=LinkKind.related, reason="r"))
    session.commit()

    assert retrieve_lessons(session, me) == []


def test_a_lesson_found_both_ways_is_returned_once(session):
    course = make_course(session)
    equation = make_skill(session, course, "equation")
    function = make_skill(session, course, "function")
    link(session, equation, function, EdgeKind.requires)
    lesson = make_principle(session, equation, "Two paths")
    session.add(PrincipleLink(principle_id=lesson.id, target_kind=LinkTargetKind.skill, target_id=function.id, kind=LinkKind.related, reason="r"))
    session.commit()

    assert titles(retrieve_lessons(session, function)) == ["Two paths"]


def test_lessons_come_back_most_recent_first_and_at_most_three(session):
    course = make_course(session)
    node = make_skill(session, course, "node")
    for minutes, name in ((50, "Oldest"), (40, "Older"), (30, "Middle"), (20, "Recent"), (10, "Most recent")):
        age(session, make_principle(session, node, name), minutes)

    assert titles(retrieve_lessons(session, node)) == ["Most recent", "Recent", "Middle"]
    assert titles(retrieve_lessons(session, node, limit=1)) == ["Most recent"]


def test_ordering_mixes_origin_and_linked_lessons_by_recency(session):
    course = make_course(session)
    me = make_skill(session, course, "me")
    far = make_skill(session, course, "far")
    own = age(session, make_principle(session, me, "My lesson"), 30)
    linked = age(session, make_principle(session, far, "Linked lesson"), 5)
    session.add(PrincipleLink(principle_id=linked.id, target_kind=LinkTargetKind.skill, target_id=me.id, kind=LinkKind.related, reason="r"))
    session.commit()

    assert titles(retrieve_lessons(session, me)) == ["Linked lesson", "My lesson"]
    assert own.id != linked.id


def test_no_lessons_at_all_is_an_empty_list(session):
    course = make_course(session)
    node = make_skill(session, course, "node")

    assert retrieve_lessons(session, node) == []


# ---------------------------------------------------------------- Challenger 用的最近 misconception


def test_recent_misconceptions_are_the_latest_first_and_limited(session):
    course = make_course(session)
    node = make_skill(session, course, "node")
    for minutes, text in ((30, "Old misconception"), (20, "Middle misconception"), (10, "Recent misconception")):
        age(session, make_principle(session, node, misconception=text), minutes)

    assert recent_misconceptions(session, 5) == ["Recent misconception", "Middle misconception", "Old misconception"]
    assert recent_misconceptions(session, 2) == ["Recent misconception", "Middle misconception"]


def test_recent_misconceptions_skip_lessons_without_one(session):
    course = make_course(session)
    node = make_skill(session, course, "node")
    make_principle(session, node, misconception=None)
    make_principle(session, node, misconception="A real misconception")

    assert recent_misconceptions(session, 5) == ["A real misconception"]


def test_recent_misconceptions_span_every_course(session):
    one = make_skill(session, make_course(session, "One"), "n")
    two = make_skill(session, make_course(session, "Two"), "n")
    age(session, make_principle(session, one, misconception="One's misconception"), 20)
    age(session, make_principle(session, two, misconception="Two's misconception"), 10)

    assert recent_misconceptions(session, 5) == ["Two's misconception", "One's misconception"]
