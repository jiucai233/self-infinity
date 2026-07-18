from sqlmodel import Session, select

from app.models import SkillNode, SkillStatus

SEED_TREE = [
    {"slug": "big-o", "title": "Big-O 记号", "description": "算法时间/空间复杂度的渐进表示法", "parent": None},
    {"slug": "recursion", "title": "递归", "description": "函数调用自身解决子问题", "parent": "big-o"},
    {"slug": "dp", "title": "动态规划", "description": "重叠子问题 + 状态转移", "parent": "recursion"},
    {"slug": "graph-bfs", "title": "图的 BFS", "description": "层序遍历与最短路径", "parent": "big-o"},
]


def seed_skill_tree(session: Session) -> None:
    existing = session.exec(select(SkillNode)).first()
    if existing:
        return

    slug_to_id: dict[str, int] = {}
    for node in SEED_TREE:
        parent_id = slug_to_id.get(node["parent"]) if node["parent"] else None
        status = SkillStatus.available if parent_id is None else SkillStatus.locked
        row = SkillNode(
            slug=node["slug"],
            title=node["title"],
            description=node["description"],
            parent_id=parent_id,
            status=status,
        )
        session.add(row)
        session.flush()
        slug_to_id[node["slug"]] = row.id

    session.commit()
