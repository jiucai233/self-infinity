"""下一步推荐官（Recommender）：在已有的节点里挑出接下来该做的几步。

三个角色的分工（对应结构图上的框）：
- **Planner**（app/agents/planner.py）编排课程——生成节点、树、先修关系，回答
  "这个领域该怎么学"；
- **Recommender**（本文件）不创造任何节点，只在已经存在的可选节点里挑几个排顺序，
  回答"我现在该干什么"；
- **Auditor** 验证掌握程度。

Recommender 是系统里唯一同时消费三路状态的角色：难度调度器（bandit）给出该挑战什么档位、
misconception 画像给出这个人反复栽在哪、体力系统给出今天扛不扛得住。这三路信息此前
各自只影响界面的一个角落，从来没有被合起来变成一个决定。
"""

import json
import logging
from dataclasses import dataclass

from app.llm.base import LLMProvider, Message, complete_with_json_retry
from app.models import SkillNode
from app.services.profile import MisconceptionCluster

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """\
你是下一步推荐官（Recommender）。为用户排出接下来 3~5 步的学习顺序。

你不负责编排课程或拆解知识结构——那是课程编排官已经做完的事。你负责的是**时间顺序**：
在下面这些已经存在的可选节点里，决定先做哪个、后做哪个，以及为什么是这个顺序。

当前可选节点：
{nodes}

系统对该用户当前状态的判断：
{context}

规则：
1. 只能从上面列出的节点里选，skill_id 必须原样出现在列表中，不得编造新节点或新 id。
2. rationale 要说清"为什么是现在做这个"——可以是难度匹配、可以是它能解锁后面的东西、
   可以是它正好撞上用户的某个老毛病。**不要复述节点标题**，那等于没给理由。
3. 如果某个节点正好对得上用户反复出现的错误心智模型，把它排前面，并在 rationale 里
   点名是哪一个心智模型。这是这份计划最有价值的部分。
4. 如果用户体力或精神偏低，把重的节点往后排，理由里说明。
5. 最多 5 步。可选节点不足 3 个时，按实际数量给，不要为了凑数重复。

只输出严格 JSON：
{{"steps": [{{"skill_id": <整数>, "rationale": "<为什么现在做这个>", "focus_hint": "<这一步要特别留意什么，一句话>"}}]}}
不要输出 JSON 之外的任何文字。
"""


@dataclass
class PlanStep:
    skill_id: int
    rationale: str
    focus_hint: str


def format_nodes(nodes: list[SkillNode], tiers: dict[int, str]) -> str:
    return "\n".join(
        f"- skill_id={n.id} 「{n.title}」（{n.node_type.value}，难度 {tiers.get(n.id, '未知')}）：{n.description}"
        for n in nodes
    )


def format_context(
    suggested_tier: str,
    context_bucket: str,
    clusters: list[MisconceptionCluster],
    health: float | None,
    sanity: float | None,
) -> str:
    lines = [
        f"- 难度调度器建议的档位：{suggested_tier}（依据用户近期状态判定为 {context_bucket}）",
    ]
    if health is not None:
        lines.append(f"- 体力值 Health：{health:.0f}")
    if sanity is not None:
        lines.append(f"- 精神值 Sanity：{sanity:.0f}")
    if not clusters:
        lines.append("- 反复出现的错误心智模型：暂无记录")
    else:
        lines.append("- 反复出现的错误心智模型：")
        for c in clusters[:5]:
            skills = "、".join(dict.fromkeys(c.skills))
            tag = "【跨领域】" if c.cross_domain else ""
            lines.append(f"    · {tag}「{c.label}」发作 {c.occurrences} 次（出现在：{skills}）")
    return "\n".join(lines)


class Recommender:
    def __init__(self, provider: LLMProvider):
        self._provider = provider

    def recommend(
        self,
        nodes: list[SkillNode],
        tiers: dict[int, str],
        suggested_tier: str,
        context_bucket: str,
        clusters: list[MisconceptionCluster],
        health: float | None = None,
        sanity: float | None = None,
    ) -> list[PlanStep]:
        if not nodes:
            return []

        system = SYSTEM_PROMPT.format(
            nodes=format_nodes(nodes, tiers),
            context=format_context(suggested_tier, context_bucket, clusters, health, sanity),
        )
        messages: list[Message] = [
            {"role": "system", "content": system},
            {"role": "user", "content": "请给出接下来的学习顺序。"},
        ]
        logger.info("recommender.recommend() calling provider=%s nodes=%d", self._provider.name, len(nodes))
        raw = complete_with_json_retry(self._provider, messages)
        return self._parse(raw, valid_ids={n.id for n in nodes})

    @staticmethod
    def _parse(raw: str, valid_ids: set[int]) -> list[PlanStep]:
        """解析并**丢弃指向不存在节点的步骤**。

        模型编造 skill_id 是必然会发生的（尤其可选节点少的时候），而一个指向空气的
        计划步骤在前端就是一个点了没反应的按钮。宁可返回更短的计划，也不返回坏的。
        """
        try:
            data = json.loads(raw)
            steps_raw = data["steps"]
            if not isinstance(steps_raw, list):
                raise ValueError("steps is not a list")
        except (json.JSONDecodeError, KeyError, TypeError, ValueError):
            logger.warning("recommender returned unusable output", exc_info=True)
            raise ValueError("推荐官未产出有效计划")

        steps: list[PlanStep] = []
        seen: set[int] = set()
        for item in steps_raw:
            try:
                skill_id = int(item["skill_id"])
            except (KeyError, TypeError, ValueError):
                continue
            if skill_id not in valid_ids or skill_id in seen:
                # 不存在的 id 直接丢；重复的也丢——同一个节点排两次是无意义的计划。
                logger.warning("recommender produced an invalid or duplicate skill_id=%s", skill_id)
                continue
            seen.add(skill_id)
            steps.append(
                PlanStep(
                    skill_id=skill_id,
                    rationale=str(item.get("rationale", "")).strip(),
                    focus_hint=str(item.get("focus_hint", "")).strip(),
                )
            )

        if not steps:
            raise ValueError("推荐官没有给出任何可用的步骤")
        return steps[:5]
