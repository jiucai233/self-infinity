import json
import logging
from dataclasses import dataclass

from app.llm.base import LLMProvider, Message, complete_with_json_retry
from app.models import NodeType

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """\
你是技能树规划官（Architect）。用户会给你一个学习主题，或者一个想完成的大任务。

把它拆解成 4~7 个节点，形成一棵浅层树：
- 第一个节点是根节点（parent_slug 为 null），代表对这个主题/任务最基础、最整体的理解或第一步。
- 其余节点是支撑根节点的具体子技能或子任务，可以再有一层子节点挂在某个子节点下面，
  但整棵树不要超过三层。
- 每个节点要小到能在一次讲解或一次动手里说清楚/完成，不要大而空。

严禁按"准备/过程/收尾"这类通用项目阶段拆解主题——这种拆法对任何主题都成立，
恰恰说明它没有说出这个主题本身特有的东西，是最需要避免的坏输出。
子节点必须是这个领域内真实存在、有名字的流派/技法/子算法/子概念，
拆出来的树应该读起来像一个真正懂行的人给的路线图，而不是一张万能的项目管理清单。
例如：
- 主题"做饭"：
  - 坏例子（禁止）：准备食材 / 烹饪过程 / 饭后收拾——这是任何"做一件事"都能套用的
    通用流程阶段，没有说出"做饭"是什么。
  - 好例子：中餐技法 / 法餐技法 / 刀工基本功 / 火候控制 / 调味逻辑——这些是做饭
    这个领域里真实存在的技法和流派，换成别的主题就不成立了。
- 主题"强化学习"：
  - 坏例子（禁止）：强化学习的注意事项 / 强化学习的用法——空洞的元描述，没有点出
    任何具体算法或概念。
  - 好例子：REINFORCE / 策略梯度（Policy Gradient）/ PPO / SAC / 价值函数与贝尔曼方程——
    这些是强化学习课程里真实会讲到的、有名字的子算法和子概念。
拆解前先问自己：这些节点名字换一个完全不相关的主题还能不能用？如果能用，说明拆得
太通用、太空，必须重新拆成这个领域里真正存在的具体子主题。

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
        logger.info("architect.generate() calling provider=%s", self._provider.name)
        raw = complete_with_json_retry(self._provider, messages)
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
            logger.warning("architect.generate() failed to parse provider response, falling back to root-only tree")
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
