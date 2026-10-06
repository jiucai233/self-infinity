"""节点位置与结构查询：全部由 contains 边决定（UT-41 ~ UT-43）。"""

import pytest
from sqlmodel import Session, SQLModel, create_engine
from sqlmodel.pool import StaticPool

from app.models import EdgeKind, NodePosition
from app.services.tree import (
    child_titles,
    contains_children,
    contains_parents,
    depth_map,
    neighbor_ids,
    node_depth,
    node_position,
)
from tests.helpers import link, make_course, make_skill


@pytest.fixture(name="session")
def session_fixture():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    SQLModel.metadata.create_all(engine)
    with Session(engine) as session:
        yield session


def test_ut41_no_contains_parent_is_root(session):
    course = make_course(session)
    solo = make_skill(session, course, "solo")

    assert node_position(session, solo) == NodePosition.root


def test_ut41_a_requires_edge_alone_does_not_make_a_node_a_child(session):
    course = make_course(session)
    a = make_skill(session, course, "a")
    b = make_skill(session, course, "b")
    link(session, a, b, EdgeKind.requires)

    assert node_position(session, b) == NodePosition.root
    assert node_position(session, a) == NodePosition.root


def test_ut42_parent_and_children_is_branch(session):
    course = make_course(session)
    root = make_skill(session, course, "root")
    mid = make_skill(session, course, "mid")
    leaf = make_skill(session, course, "leaf")
    link(session, root, mid, EdgeKind.contains)
    link(session, mid, leaf, EdgeKind.contains)

    assert node_position(session, mid) == NodePosition.branch
    assert node_position(session, root) == NodePosition.root


def test_ut43_parent_without_children_is_leaf(session):
    course = make_course(session)
    root = make_skill(session, course, "root")
    leaf = make_skill(session, course, "leaf")
    link(session, root, leaf, EdgeKind.contains)

    assert node_position(session, leaf) == NodePosition.leaf


def test_position_is_by_edges_not_by_depth(session):
    # 一条两层的分支和一条四层的分支：两层分支的叶子，和四层分支的中间节点，深度一样。
    course = make_course(session)
    root = make_skill(session, course, "root")
    short_leaf = make_skill(session, course, "short-leaf")
    a = make_skill(session, course, "a")
    b = make_skill(session, course, "b")
    c = make_skill(session, course, "c")
    link(session, root, short_leaf, EdgeKind.contains)
    link(session, root, a, EdgeKind.contains)
    link(session, a, b, EdgeKind.contains)
    link(session, b, c, EdgeKind.contains)

    assert node_depth(session, short_leaf) == node_depth(session, a) == 1
    assert node_position(session, short_leaf) == NodePosition.leaf
    assert node_position(session, a) == NodePosition.branch


def test_children_and_titles_follow_contains_edges_only(session):
    course = make_course(session)
    root = make_skill(session, course, "root")
    first = make_skill(session, course, "first", "First")
    second = make_skill(session, course, "second", "Second")
    other = make_skill(session, course, "other", "Unrelated")
    link(session, root, second, EdgeKind.contains)
    link(session, root, first, EdgeKind.contains)
    link(session, root, other, EdgeKind.requires)

    # 按节点 id 排序，不按边创建顺序，结果才稳定。
    assert [n.slug for n in contains_children(session, root.id)] == ["first", "second"]
    assert child_titles(session, root) == ["First", "Second"]


def test_a_node_with_two_parents_lists_the_main_parent_first(session):
    course = make_course(session)
    root = make_skill(session, course, "root")
    calculus = make_skill(session, course, "calculus")
    sequences = make_skill(session, course, "sequences")
    limit = make_skill(session, course, "limit")
    link(session, root, calculus, EdgeKind.contains)
    link(session, root, sequences, EdgeKind.contains)
    link(session, sequences, limit, EdgeKind.contains, primary=False)
    link(session, calculus, limit, EdgeKind.contains, primary=True)

    assert [p.slug for p in contains_parents(session, limit.id)] == ["calculus", "sequences"]
    assert node_position(session, limit) == NodePosition.leaf


def test_depth_follows_the_main_parent_chain(session):
    course = make_course(session)
    root = make_skill(session, course, "root")
    shallow = make_skill(session, course, "shallow")
    mid = make_skill(session, course, "mid")
    deep = make_skill(session, course, "deep")
    both = make_skill(session, course, "both")
    link(session, root, shallow, EdgeKind.contains)
    link(session, root, mid, EdgeKind.contains)
    link(session, mid, deep, EdgeKind.contains)
    link(session, shallow, both, EdgeKind.contains, primary=True)
    link(session, deep, both, EdgeKind.contains, primary=False)

    assert node_depth(session, root) == 0
    assert node_depth(session, both) == 2  # via shallow (the main parent), not via deep
    depths = depth_map(session)
    assert depths[deep.id] == 2 and depths[both.id] == 2
    assert root.id not in depths  # the root has no contains edge; callers default to 0


def test_neighbors_include_both_edge_kinds_in_both_directions(session):
    course = make_course(session)
    parent = make_skill(session, course, "parent")
    me = make_skill(session, course, "me")
    child = make_skill(session, course, "child")
    before = make_skill(session, course, "before")
    after = make_skill(session, course, "after")
    stranger = make_skill(session, course, "stranger")
    link(session, parent, me, EdgeKind.contains)
    link(session, me, child, EdgeKind.contains)
    link(session, before, me, EdgeKind.requires)
    link(session, me, after, EdgeKind.requires)

    assert neighbor_ids(session, me.id) == {parent.id, child.id, before.id, after.id}
    assert stranger.id not in neighbor_ids(session, me.id)
