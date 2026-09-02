"""先修边的落库与环检测。

先修关系必须是**有向无环图**：一旦成环（A 要先会 B，B 要先会 A），课程就没有任何
合法的起点，排课直接失效。模型偶尔会产出这种边——尤其在两个概念互相依赖、人类也
说不清谁先谁后的时候——所以入库前必须挡住。

策略是逐条尝试、遇环即弃，而不是整批拒绝：一条坏边不该让整棵树的先修信息全部丢掉。
"""

import logging
from collections import defaultdict

from sqlmodel import Session, select

from app.models import SkillPrerequisite

logger = logging.getLogger(__name__)


def _reaches(adjacency: dict[int, set[int]], start: int, target: int) -> bool:
    """从 start 沿先修边能否走到 target。迭代 DFS，避免深树递归爆栈。"""
    stack = [start]
    seen: set[int] = set()
    while stack:
        node = stack.pop()
        if node == target:
            return True
        if node in seen:
            continue
        seen.add(node)
        stack.extend(adjacency.get(node, ()))
    return False


def add_prerequisites(session: Session, edges: list[tuple[int, int, str]]) -> int:
    """加入先修边（每条是 (skill_id, prerequisite_id, reason)），跳过重复与成环的。

    返回实际写入的条数。调用方负责 commit。
    """
    existing = session.exec(select(SkillPrerequisite)).all()

    # adjacency[x] = {y}：x 依赖 y（学 x 之前要先会 y）。
    adjacency: dict[int, set[int]] = defaultdict(set)
    for row in existing:
        adjacency[row.skill_id].add(row.prerequisite_id)
    seen = {(row.skill_id, row.prerequisite_id) for row in existing}

    added = 0
    for skill_id, prerequisite_id, reason in edges:
        if skill_id == prerequisite_id or (skill_id, prerequisite_id) in seen:
            continue
        # 加入 skill -> prerequisite 会成环，当且仅当 prerequisite 已经能走到 skill。
        if _reaches(adjacency, prerequisite_id, skill_id):
            logger.warning(
                "dropping prerequisite %s -> %s: it would create a cycle", skill_id, prerequisite_id
            )
            continue
        session.add(
            SkillPrerequisite(skill_id=skill_id, prerequisite_id=prerequisite_id, reason=reason)
        )
        adjacency[skill_id].add(prerequisite_id)
        seen.add((skill_id, prerequisite_id))
        added += 1

    return added
