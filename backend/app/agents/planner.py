"""课程编排官（Planner）：把一个主题编排成一门课。

输出两样东西，它们长在同一批节点上，但含义完全不同：

1. **一棵树**（每个节点一条 parent 边）——分类关系，回答"这个领域由哪些部分组成"。
   它决定界面怎么组织、节点怎么导航。
2. **一张先修图**（任意条数的边，可跨分支）——学习顺序，回答"学 B 之前要先会什么"。
   它决定课程怎么排。

两者必须分开，因为树的遍历顺序**不等于**学习顺序。最直接的例子是兄弟节点：
Fast R-CNN 和 Faster R-CNN 在树上是同一个父亲下的平级节点，彼此没有关系；但后者
的全部要点就是"把前者的 Selective Search 换成 RPN"，不懂前者根本听不懂后者。这条
顺序树里表达不了，只能靠先修边。跨分支的例子是 Perceptron——它在树上只能挂一个
地方，却是 CV / NLP / RL 三个分支共同的前置。

**根节点的写法是这次改造的重点**。上一版 prompt 要求根节点"代表对这个主题最基础、
最整体的理解"，直接导致「机器人学基础」「GPU与AI计算概览」这类概览式根节点——而
那种节点没法审计，问「讲讲机器人学基础」得不到任何有深浅之分的回答。节点粒度决定
审计质量的上限，所以现在根节点被明确定义为纯容器，可审计性的要求压在叶子上。
"""

import json
import logging
from dataclasses import dataclass, field

from app.llm.base import LLMProvider, Message, complete_with_json_retry
from app.models import NodeType

logger = logging.getLogger(__name__)

# 课程规模的默认值。12 个节点是个折中：4~7（上一版）拆不出真实课程的分辨率，
# 而节点越多，单次生成的质量越不可控，也越容易出现凑数的空节点。
DEFAULT_NODE_COUNT = 12
DEFAULT_MAX_DEPTH = 4

DEPTH_PROFILES = {
    "intro": "入门：叶子停在'这是什么、为什么需要它'的层面，不深入具体算法细节。",
    "standard": "标准：叶子落在具体方法上（例如具体的算法、具体的技法），能问出机制。",
    "deep": "深入：叶子落到具体的模型/论文级对象上（例如 Faster R-CNN 而不是'目标检测'），"
    "能问出实现取舍。",
}

SYSTEM_PROMPT = """\
你是课程编排官（Planner）。用户会给你一个学习主题，或者一个想完成的大任务。
你要为它编排一门课：一棵分类树，外加节点之间的先修关系。

## 树的形状

- **根节点**（parent_slug 为 null）就是这个主题本身，**只是一个容器**。
  不要写成「XX基础」「XX概览」「XX入门整体理解」这类整体介绍——那种节点无法被审计，
  问「讲讲XX基础」得不到任何有深浅之分的回答。根节点的 description 说明这门课覆盖
  什么范围就够了。
- **中间节点**是分类。它的价值在于统摄下面挂的东西，所以它应该是一个真实存在的类别
  名（例如「目标检测」「两阶段方法」），而不是一段介绍。
- **叶子节点**是真正被审计的对象，必须具体到能对它提出**有明确对错**的问题。
  好叶子：「Faster R-CNN」——可以问 RPN 相比 Selective Search 省在哪。
  坏叶子：「深度学习基础」——问不出任何有深浅之分的东西。

判断拆够了没有：**如果一个叶子节点你想不出三个有明确对错的问题，说明它还太粗，继续拆。**

## 规模

- 总共 {node_count} 个节点左右（可以有正负一两个的出入，不要为了凑数塞空节点）
- 最多 {max_depth} 层
- 深度定位：{depth_profile}

## 拆解质量

严禁按"准备/过程/收尾"这类通用项目阶段拆解主题——这种拆法对任何主题都成立，
恰恰说明它没有说出这个主题本身特有的东西。节点必须是这个领域里真实存在、有名字的
流派/技法/子算法/子概念。
拆解前先自问：这些节点名字换一个完全不相关的主题还能不能用？如果能用，说明拆得太空，
必须重拆。

例如主题「做饭」：
- 坏：准备食材 / 烹饪过程 / 饭后收拾——任何"做一件事"都能套用。
- 好：刀工基本功 / 火候控制 / 乳化类酱汁 / 美拉德反应——这个领域里真实存在的技法。

## node_type

每个节点标注 node_type，二选一：
- "concept"：需要理解「为什么成立」的知识点（原理、机制、权衡）。
- "task"：具体可执行的步骤，做没做到一目了然。

## 先修关系

除了树，再给出先修边：**学 to 之前必须先会 from**。

**先修关系和父子关系是两回事，不要把父子边抄一遍。** 父子是"属于"，先修是"顺序"。
- 先修常常出现在**兄弟之间**：Fast R-CNN 是 Faster R-CNN 的先修，它俩在树上是平级的。
- 先修可以**跨分支**：Perceptron 挂在「基础」下，却是 CV、NLP、RL 共同的先修。
- **大多数节点没有先修。** 不要为了凑数硬加——只在"不先会 A 就真的听不懂 B"时才给。

## 输出

只输出严格 JSON：
{{"nodes": [{{"slug": "<小写字母数字连字符，本次输出内唯一>", "title": "<不超过16字>",
  "description": "<一句话说明这个节点具体是什么>", "parent_slug": "<某个 slug 或 null>",
  "node_type": "concept" 或 "task"}}],
 "prerequisites": [{{"from": "<先修节点的 slug>", "to": "<需要它的 slug>", "reason": "<一句话>"}}]}}
不要输出 JSON 之外的任何文字。
"""


@dataclass
class GeneratedNode:
    slug: str
    title: str
    description: str
    parent_slug: str | None
    node_type: NodeType = NodeType.concept


@dataclass
class GeneratedPrerequisite:
    from_slug: str
    to_slug: str
    reason: str


@dataclass
class GeneratedCourse:
    nodes: list[GeneratedNode]
    prerequisites: list[GeneratedPrerequisite] = field(default_factory=list)


class Planner:
    def __init__(self, provider: LLMProvider):
        self._provider = provider

    def generate(
        self,
        topic: str,
        node_count: int = DEFAULT_NODE_COUNT,
        max_depth: int = DEFAULT_MAX_DEPTH,
        difficulty: str = "standard",
    ) -> GeneratedCourse:
        system = SYSTEM_PROMPT.format(
            node_count=node_count,
            max_depth=max_depth,
            depth_profile=DEPTH_PROFILES.get(difficulty, DEPTH_PROFILES["standard"]),
        )
        messages: list[Message] = [
            {"role": "system", "content": system},
            {"role": "user", "content": topic},
        ]
        logger.info(
            "planner.generate() calling provider=%s node_count=%d difficulty=%s",
            self._provider.name,
            node_count,
            difficulty,
        )
        raw = complete_with_json_retry(self._provider, messages)
        return self._parse(raw, topic)

    @staticmethod
    def _parse(raw: str, topic: str) -> GeneratedCourse:
        try:
            data = json.loads(raw)
            # 容忍裸数组：早期格式只有节点没有先修边，没必要因为格式演进就判定失败。
            items = data["nodes"] if isinstance(data, dict) else data
            if not isinstance(items, list) or not items:
                raise ValueError("empty or non-list nodes")
            nodes = [
                GeneratedNode(
                    slug=str(item["slug"]),
                    title=str(item["title"]),
                    description=str(item["description"]),
                    parent_slug=item.get("parent_slug"),
                    node_type=NodeType(item.get("node_type", "concept")),
                )
                for item in items
            ]
        except (json.JSONDecodeError, KeyError, TypeError, ValueError):
            logger.warning("planner.generate() failed to parse response, falling back to root-only tree")
            return GeneratedCourse(
                nodes=[
                    GeneratedNode(
                        slug="root",
                        title=topic[:16] or "新主题",
                        description=f"关于「{topic}」的课程",
                        parent_slug=None,
                        node_type=NodeType.concept,
                    )
                ]
            )

        if nodes[0].parent_slug is not None:
            nodes[0].parent_slug = None

        prerequisites = Planner._parse_prerequisites(
            data if isinstance(data, dict) else {}, {n.slug for n in nodes}
        )
        return GeneratedCourse(nodes=nodes, prerequisites=prerequisites)

    @staticmethod
    def _parse_prerequisites(data: dict, valid_slugs: set[str]) -> list[GeneratedPrerequisite]:
        """解析先修边，丢弃无效的。

        丢弃三类：指向不存在 slug 的（模型编造）、自环、以及重复。**不在这里做环检测**
        ——一条边看不出环，整体成环与否要等落库拿到真实 id 之后再判（见 routers/skills.py）。
        """
        raw_edges = data.get("prerequisites") or []
        if not isinstance(raw_edges, list):
            return []

        edges: list[GeneratedPrerequisite] = []
        seen: set[tuple[str, str]] = set()
        for item in raw_edges:
            try:
                from_slug = str(item["from"])
                to_slug = str(item["to"])
            except (KeyError, TypeError):
                continue
            if from_slug not in valid_slugs or to_slug not in valid_slugs:
                logger.warning("planner produced a prerequisite over unknown slugs: %s -> %s", from_slug, to_slug)
                continue
            if from_slug == to_slug or (from_slug, to_slug) in seen:
                continue
            seen.add((from_slug, to_slug))
            edges.append(
                GeneratedPrerequisite(
                    from_slug=from_slug, to_slug=to_slug, reason=str(item.get("reason", "")).strip()
                )
            )
        return edges
