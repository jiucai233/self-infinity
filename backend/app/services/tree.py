"""技能树的位置查询。

节点在树里的位置决定该怎么审计它，这是比 node_type（concept/task）更细的一个维度：

- **叶子**下面什么都没有，它就是最具体的那个单元，问实现细节。
- **中间节点**的全部价值在于它统摄了下面挂的东西，所以该问的是那些孩子**之间**的
  关系与取舍——问"这是什么"等于浪费了它的位置。
- **根节点**是容器，问它自己没有意义，该问的是这门课的适用边界。

刻意用"有没有子节点"而不是"绝对深度"来判位置。同一棵树里不同分支的深度含义并不
一致：CV 分支可能挖到五层（CV → 检测 → 两阶段 → Faster R-CNN），RL 分支两层就到底，
那么 RL 的叶子和 CV 的中间节点深度相同、抽象程度却完全不同。按深度分会分错。
"""

from enum import StrEnum

from sqlmodel import Session, select

from app.models import SkillNode


class NodePosition(StrEnum):
    root = "root"
    branch = "branch"
    leaf = "leaf"


def children_of(session: Session, skill: SkillNode) -> list[SkillNode]:
    return session.exec(select(SkillNode).where(SkillNode.parent_id == skill.id)).all()


def node_position(session: Session, skill: SkillNode) -> NodePosition:
    """判断节点位置。

    没有子节点就是叶子——**即使它同时没有父节点**。一棵只有一个节点的树（Planner
    解析失败时的兜底产物）那个节点应当按叶子审计，因为它确实是最具体的那个东西，
    按根节点去问"这门课的边界"会得到一场空洞的对话。
    """
    if not children_of(session, skill):
        return NodePosition.leaf
    if skill.parent_id is None:
        return NodePosition.root
    return NodePosition.branch


def child_titles(session: Session, skill: SkillNode) -> list[str]:
    """子节点标题，用于让审计官问出"这些东西之间"的问题。"""
    return [c.title for c in children_of(session, skill)]
