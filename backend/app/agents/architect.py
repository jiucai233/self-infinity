import json
from dataclasses import dataclass

from app.llm.base import LLMProvider, Message
from app.models import NodeType

SYSTEM_PROMPT = """\
你是技能树规划官（Architect）。用户会给你一个学习主题，或者一个想完成的大任务。

把它拆解成 4~7 个节点，形成一棵浅层树：
- 第一个节点是根节点（parent_slug 为 null），代表对这个主题/任务最基础、最整体的理解或第一步。
- 其余节点是支撑根节点的具体子技能或子任务，可以再有一层子节点挂在某个子节点下面，
  但整棵树不要超过三层。
- 每个节点要小到能在一次讲解或一次动手里说清楚/完成，不要大而空。

每个节点还要标注 node_type，二选一：
- "concept"：一个需要理解「为什么成立」的知识点，比如原理、机制、权衡。
- "task"：一个具体可执行的步骤，做没做到一目了然，不需要深挖底层原理。
  例如"把大象放进冰箱"这种任务，"打开冰箱门"就是 task，不是 concept——
  不要为了凑深度硬把纯步骤类节点包装成需要解释原理的知识点。
判断依据：如果这个节点的验证方式应该是"讲清楚为什么"，标 concept；
如果应该是"确认真的做了/知道怎么做"，标 task。同一批节点里 concept 和 task 可以混合。

只输出严格 JSON 数组，每个元素形如：
{"slug": "<小写字母数字连字符，本次输出内唯一>", "title": "<节点标题，不超过16字>",
 "description": "<一句话说明这个节点具体是什么>", "parent_slug": "<某个 slug 或 null>",
 "node_type": "concept" 或 "task"}

不要输出 JSON 数组之外的任何文字。
"""


@dataclass
class GeneratedNode:
    slug: str
    title: str
    description: str
    parent_slug: str | None
    node_type: NodeType = NodeType.concept


class Architect:
    def __init__(self, provider: LLMProvider):
        self._provider = provider

    def generate(self, topic: str) -> list[GeneratedNode]:
        messages: list[Message] = [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": topic},
        ]
        raw = self._provider.complete(messages)
        try:
            data = json.loads(raw)
            if not isinstance(data, list) or not data:
                raise ValueError("empty or non-list response")
            nodes = [
                GeneratedNode(
                    slug=str(item["slug"]),
                    title=str(item["title"]),
                    description=str(item["description"]),
                    parent_slug=item.get("parent_slug"),
                    node_type=NodeType(item.get("node_type", "concept")),
                )
                for item in data
            ]
        except (json.JSONDecodeError, KeyError, TypeError, ValueError):
            nodes = [
                GeneratedNode(
                    slug="root",
                    title=topic[:16] or "新主题",
                    description=f"关于「{topic}」的入门理解",
                    parent_slug=None,
                    node_type=NodeType.concept,
                )
            ]

        if nodes[0].parent_slug is not None:
            nodes[0].parent_slug = None
        return nodes
