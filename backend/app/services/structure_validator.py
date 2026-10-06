"""Structure Validator（plan 7.4，纯代码，不调用 LLM）：课程落库前先清洗 Planner 的输出。

Planner 的输出会以可预测的方式出错：边指向不存在的节点、重复、成环，或者让课程自相矛盾、
没法学完。这里按计划表里的 11 条规则依次处理，并按规则编号记录每条规则处理了多少处，
供课程质量检查使用（plan 12.5）。清洗之后的课程满足 plan 8.3 的全部性质：

- 恰好一个根；
- contains 和 requires 都无环；
- 每个非根节点有 1-3 个 contains 父节点，其中恰好一个是主父节点（第一个）；
- 没有 requires 边连着一个节点和它自己的祖先或后代；
- 没有边指向课程之外。

只有规则 5 会让整次生成失败（调用方重试一次 Planner，再失败就 502）；重复 slug 同理，
因为那会让"哪个节点属于谁"本身变得有歧义。

规则 4-8 先把 contains 这一层定下来，因为规则 10-11 要用最终的祖先关系。
"""

from collections import deque
from dataclasses import dataclass, field

from app.agents.planner import PlannedCourse, PlannedNode, PlannedRequire

MAX_PARENTS = 3

RULE_UNKNOWN_SLUG = 1
RULE_SELF_EDGE = 2
RULE_DUPLICATE_EDGE = 3
RULE_CONTAINS_LOOP = 4
RULE_ROOT_COUNT = 5
RULE_ORPHAN = 6
RULE_TOO_MANY_PARENTS = 7
RULE_TOO_DEEP = 8
RULE_REQUIRES_LOOP = 9
RULE_REQUIRES_ANCESTOR = 10
RULE_REQUIRES_DESCENDANT = 11


class StructureError(Exception):
    """The Planner output cannot be repaired by dropping edges (rule 5)."""


@dataclass
class ValidatedCourse:
    root_slug: str
    nodes: list[PlannedNode]
    # slug -> contains parents after cleaning; the first one is the main parent.
    parents: dict[str, list[str]]
    requires: list[PlannedRequire]
    # rule number -> how many edges / nodes it removed or fixed.
    removals: dict[int, int] = field(default_factory=dict)
    # Longest contains path from the root, counted in nodes (the root alone is 1 level).
    levels: int = 1
    depth_exceeded: bool = False

    def main_parent(self, slug: str) -> str | None:
        parents = self.parents.get(slug) or []
        return parents[0] if parents else None


def _reaches(adjacency: dict[str, list[str]], start: str, target: str) -> bool:
    """Iterative DFS; deep courses must not blow the recursion limit."""
    stack, seen = [start], set()
    while stack:
        node = stack.pop()
        if node == target:
            return True
        if node in seen:
            continue
        seen.add(node)
        stack.extend(adjacency.get(node, ()))
    return False


def _ancestors(parents: dict[str, list[str]]) -> dict[str, set[str]]:
    result: dict[str, set[str]] = {}

    def of(slug: str) -> set[str]:
        if slug in result:
            return result[slug]
        found: set[str] = set()
        stack = list(parents.get(slug, ()))
        while stack:
            parent = stack.pop()
            if parent in found:
                continue
            found.add(parent)
            stack.extend(parents.get(parent, ()))
        result[slug] = found
        return found

    for slug in parents:
        of(slug)
    return result


def _levels(root: str, parents: dict[str, list[str]]) -> int:
    """Longest contains path from the root, counted in nodes (Kahn's algorithm over the DAG)."""
    children: dict[str, list[str]] = {slug: [] for slug in parents}
    waiting = {slug: len(plist) for slug, plist in parents.items()}
    for child, plist in parents.items():
        for parent in plist:
            children[parent].append(child)
    level = {root: 1}
    queue = deque(slug for slug, count in waiting.items() if count == 0)
    while queue:
        node = queue.popleft()
        for child in children[node]:
            level[child] = max(level.get(child, 0), level.get(node, 1) + 1)
            waiting[child] -= 1
            if waiting[child] == 0:
                queue.append(child)
    return max(level.values())


def validate_structure(course: PlannedCourse, max_depth: int) -> ValidatedCourse:
    removals = {rule: 0 for rule in range(1, 12)}
    nodes = course.nodes
    slugs = [n.slug for n in nodes]
    known = set(slugs)

    if len(known) != len(slugs):
        raise StructureError("slugs must be unique within the output")

    # Rules 1-3: contains edges (the `parents` lists).
    parents: dict[str, list[str]] = {}
    for node in nodes:
        kept: list[str] = []
        for parent in node.parents:
            if parent not in known:
                removals[RULE_UNKNOWN_SLUG] += 1
            elif parent == node.slug:
                removals[RULE_SELF_EDGE] += 1
            elif parent in kept:
                removals[RULE_DUPLICATE_EDGE] += 1
            else:
                kept.append(parent)
        parents[node.slug] = kept

    # Rules 1-3: requires edges.
    requires: list[PlannedRequire] = []
    seen_requires: set[tuple[str, str]] = set()
    for edge in course.requires:
        if edge.from_slug not in known or edge.to_slug not in known:
            removals[RULE_UNKNOWN_SLUG] += 1
        elif edge.from_slug == edge.to_slug:
            removals[RULE_SELF_EDGE] += 1
        elif (edge.from_slug, edge.to_slug) in seen_requires:
            removals[RULE_DUPLICATE_EDGE] += 1
        else:
            seen_requires.add((edge.from_slug, edge.to_slug))
            requires.append(edge)

    # Rule 4: drop the contains edge that closes a loop. Edges are tried in output
    # order, so the one added last is the one that closes it.
    children: dict[str, list[str]] = {slug: [] for slug in slugs}
    accepted: dict[str, list[str]] = {slug: [] for slug in slugs}
    for node in nodes:
        for parent in parents[node.slug]:
            if _reaches(children, node.slug, parent):
                removals[RULE_CONTAINS_LOOP] += 1
                continue
            children[parent].append(node.slug)
            accepted[node.slug].append(parent)
    parents = accepted

    # Rule 5: the root is the one node the Planner gave no parents. Counting the
    # declared roots (not the nodes left without a parent after cleaning) is what
    # lets rule 6 exist: a node whose only parent was bad still *meant* to be a child.
    roots = [n.slug for n in nodes if not n.parents]
    if len(roots) != 1:
        raise StructureError(f"expected exactly one node without parents, found {len(roots)}")
    root = roots[0]

    # Rule 6: a non-root node with no valid parent left hangs off the root.
    for node in nodes:
        if node.slug != root and not parents[node.slug]:
            parents[node.slug] = [root]
            removals[RULE_ORPHAN] += 1

    # Rule 7: at most 3 parents, the first three kept.
    for slug, plist in parents.items():
        if len(plist) > MAX_PARENTS:
            removals[RULE_TOO_MANY_PARENTS] += len(plist) - MAX_PARENTS
            parents[slug] = plist[:MAX_PARENTS]

    # Rule 8: too deep is a quality issue, not a structural one — keep, but record.
    ancestors = _ancestors(parents)
    levels = _levels(root, parents)
    depth_exceeded = levels > max_depth
    if depth_exceeded:
        removals[RULE_TOO_DEEP] += 1

    # Rule 9: drop the requires edge that closes a loop.
    forward: dict[str, list[str]] = {slug: [] for slug in slugs}
    acyclic: list[PlannedRequire] = []
    for edge in requires:
        if _reaches(forward, edge.to_slug, edge.from_slug):
            removals[RULE_REQUIRES_LOOP] += 1
            continue
        forward[edge.from_slug].append(edge.to_slug)
        acyclic.append(edge)

    # Rule 10: "to requires from" where from is already an ancestor of to. A node only
    # opens after one of its parents is mastered, so this is implied.
    no_ancestors: list[PlannedRequire] = []
    for edge in acyclic:
        if edge.from_slug in ancestors[edge.to_slug]:
            removals[RULE_REQUIRES_ANCESTOR] += 1
        else:
            no_ancestors.append(edge)

    # Rule 11: "to requires from" where from is a descendant of to. The descendant stays
    # locked until `to` is mastered, so this could never be satisfied.
    final: list[PlannedRequire] = []
    for edge in no_ancestors:
        if edge.to_slug in ancestors[edge.from_slug]:
            removals[RULE_REQUIRES_DESCENDANT] += 1
        else:
            final.append(edge)

    return ValidatedCourse(
        root_slug=root,
        nodes=nodes,
        parents=parents,
        requires=final,
        removals=removals,
        levels=levels,
        depth_exceeded=depth_exceeded,
    )
