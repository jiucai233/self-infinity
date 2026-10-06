"""Structure Validator：Planner 输出落库前的 11 条清洗规则（plan 7.4，UT-30 ~ UT-40）。"""

import pytest

from app.agents.planner import PlannedCourse, PlannedNode, PlannedRequire
from app.services.structure_validator import StructureError, validate_structure


def node(slug: str, *parents: str) -> PlannedNode:
    return PlannedNode(slug=slug, title=slug, description=f"{slug} description", parents=list(parents))


def requires(*pairs: tuple[str, str]) -> list[PlannedRequire]:
    return [PlannedRequire(from_slug=a, to_slug=b, reason="Reason") for a, b in pairs]


def course(nodes: list[PlannedNode], reqs: list[PlannedRequire] | None = None) -> PlannedCourse:
    return PlannedCourse(nodes=nodes, requires=reqs or [])


def pairs(validated) -> list[tuple[str, str]]:
    return [(r.from_slug, r.to_slug) for r in validated.requires]


# ---------------------------------------------------------------- 规则 1-3：坏边


def test_ut30_unknown_slug_edge_is_dropped():
    c = course(
        [node("root"), node("a", "root", "ghost"), node("b", "root")],
        requires(("a", "ghost"), ("a", "b")),
    )

    result = validate_structure(c, max_depth=4)

    assert result.parents["a"] == ["root"]
    assert pairs(result) == [("a", "b")]
    assert result.removals[1] == 2


def test_ut31_self_loop_is_dropped():
    c = course([node("root"), node("a", "root", "a"), node("b", "root")], requires(("b", "b"), ("a", "b")))

    result = validate_structure(c, max_depth=4)

    assert result.parents["a"] == ["root"]
    assert pairs(result) == [("a", "b")]
    assert result.removals[2] == 2


def test_ut32_duplicate_edge_keeps_one():
    c = course(
        [node("root"), node("a", "root", "root"), node("b", "root")],
        requires(("a", "b"), ("a", "b")),
    )

    result = validate_structure(c, max_depth=4)

    assert result.parents["a"] == ["root"]
    assert pairs(result) == [("a", "b")]
    assert result.removals[3] == 2


# ---------------------------------------------------------------- 规则 4-8：contains 这一层


def test_ut33_contains_cycle_closing_edge_is_dropped():
    # b 说自己属于 a 和 c，c 说自己属于 b：b -> c 这条边把环闭上，丢掉它。
    c = course([node("root"), node("a", "root"), node("b", "a", "c"), node("c", "b")])

    result = validate_structure(c, max_depth=4)

    assert result.removals[4] == 1
    assert result.parents["b"] == ["a", "c"]
    # c 唯一的父节点被丢了，规则 6 把它挂回根下。
    assert result.parents["c"] == ["root"]


def test_ut33_two_node_cycle_is_broken_too():
    c = course([node("root"), node("a", "root", "b"), node("b", "a")])

    result = validate_structure(c, max_depth=4)

    assert result.removals[4] == 1
    assert result.parents["a"] == ["root", "b"]
    assert result.parents["b"] == ["root"]


def test_ut34_two_roots_is_a_structure_error():
    c = course([node("root"), node("other-root"), node("a", "root")])

    with pytest.raises(StructureError):
        validate_structure(c, max_depth=4)


def test_ut34_no_root_is_a_structure_error():
    c = course([node("a", "b"), node("b", "a")])

    with pytest.raises(StructureError):
        validate_structure(c, max_depth=4)


def test_duplicate_slugs_are_a_structure_error():
    c = course([node("root"), node("a", "root"), node("a", "root")])

    with pytest.raises(StructureError):
        validate_structure(c, max_depth=4)


def test_ut35_node_with_no_valid_parent_left_hangs_off_the_root():
    c = course([node("root"), node("a", "ghost"), node("b", "a")])

    result = validate_structure(c, max_depth=4)

    assert result.parents["a"] == ["root"]
    assert result.parents["b"] == ["a"]
    assert result.removals[6] == 1


def test_ut36_more_than_three_parents_keeps_the_first_three():
    c = course(
        [node("root"), node("a", "root"), node("b", "root"), node("c", "root"), node("d", "root"),
         node("x", "a", "b", "c", "d")]
    )

    result = validate_structure(c, max_depth=4)

    assert result.parents["x"] == ["a", "b", "c"]
    assert result.removals[7] == 1


def test_ut40_every_non_root_node_has_exactly_one_main_parent():
    c = course(
        [node("root"), node("a", "root"), node("b", "root"), node("x", "a", "b"), node("y", "ghost")]
    )

    result = validate_structure(c, max_depth=4)

    for n in c.nodes:
        if n.slug == result.root_slug:
            assert result.main_parent(n.slug) is None
        else:
            assert result.parents[n.slug], n.slug
            assert result.main_parent(n.slug) == result.parents[n.slug][0]
    assert result.main_parent("x") == "a"
    assert result.root_slug == "root"


def test_main_parent_is_the_first_surviving_parent_not_the_first_declared():
    # 声明的第一个父节点是 ghost，被丢了以后，第二个成为主父节点。
    c = course([node("root"), node("a", "ghost", "root")])

    assert validate_structure(c, max_depth=4).main_parent("a") == "root"


def test_rule_8_too_deep_is_kept_and_recorded():
    c = course([node("root"), node("a", "root"), node("b", "a"), node("c", "b")])

    deep = validate_structure(c, max_depth=3)
    fine = validate_structure(c, max_depth=4)

    assert deep.levels == 4 and deep.depth_exceeded and deep.removals[8] == 1
    assert [n.slug for n in deep.nodes] == ["root", "a", "b", "c"]  # nothing removed
    assert fine.levels == 4 and not fine.depth_exceeded and fine.removals[8] == 0


def test_levels_follow_the_longest_path_through_a_second_parent():
    # x 同时属于 a（第 2 层）和 deep（第 4 层）：最长路径经过第二个父节点。
    c = course(
        [node("root"), node("a", "root"), node("m", "root"), node("n", "m"), node("deep", "n"),
         node("x", "a", "deep")]
    )

    assert validate_structure(c, max_depth=6).levels == 5


# ---------------------------------------------------------------- 规则 9-11：requires 这一层


def test_ut37_requires_cycle_closing_edge_is_dropped():
    c = course(
        [node("root"), node("a", "root"), node("b", "root"), node("c", "root")],
        requires(("a", "b"), ("b", "c"), ("c", "a")),
    )

    result = validate_structure(c, max_depth=4)

    assert pairs(result) == [("a", "b"), ("b", "c")]
    assert result.removals[9] == 1


def test_ut38_node_that_requires_its_own_ancestor_edge_is_dropped():
    # algebra 是 quadratic 的祖先：quadratic 要求 algebra 已经隐含在 contains 里。
    c = course(
        [node("root"), node("algebra", "root"), node("quadratic", "algebra"), node("leaf", "quadratic")],
        requires(("algebra", "quadratic"), ("root", "leaf")),
    )

    result = validate_structure(c, max_depth=4)

    assert pairs(result) == []
    assert result.removals[10] == 2


def test_ut39_node_that_requires_its_own_descendant_edge_is_dropped():
    # algebra 要求它自己的后代 quadratic：后代在 algebra 通过前一直锁着，永远满足不了。
    c = course(
        [node("root"), node("algebra", "root"), node("quadratic", "algebra")],
        requires(("quadratic", "algebra")),
    )

    result = validate_structure(c, max_depth=4)

    assert pairs(result) == []
    assert result.removals[11] == 1


def test_requires_between_unrelated_branches_survives():
    c = course(
        [node("root"), node("a", "root"), node("b", "root"), node("a1", "a"), node("b1", "b")],
        requires(("a1", "b1")),
    )

    assert pairs(validate_structure(c, max_depth=4)) == [("a1", "b1")]


def test_ancestor_relation_uses_every_parent_not_only_the_main_one():
    # x 属于 a 和 b；b 是 x 的（次要）父节点，所以 b 是 x 的祖先。
    c = course(
        [node("root"), node("a", "root"), node("b", "root"), node("x", "a", "b")],
        requires(("b", "x")),
    )

    result = validate_structure(c, max_depth=4)

    assert pairs(result) == []
    assert result.removals[10] == 1


def test_a_clean_course_passes_through_unchanged():
    c = course(
        [node("root"), node("a", "root"), node("b", "root"), node("x", "a", "b")],
        requires(("a", "b")),
    )

    result = validate_structure(c, max_depth=4)

    assert result.parents == {"root": [], "a": ["root"], "b": ["root"], "x": ["a", "b"]}
    assert pairs(result) == [("a", "b")]
    assert sum(result.removals.values()) == 0
