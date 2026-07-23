import json
import logging

from app.llm.base import LLMProvider, Message, complete_with_json_retry

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """\
你是原则蒸馏官（Scribe）。用户在技能「{skill_title}」的费曼审计中失败了，
暴露出的问题是：{gaps}。用户对失败的反思是："{reflection}"

先诊断用户失败背后那个"错误的心智模型"是什么——不是表面上答错了什么，而是他到底
以为什么是对的、导致了这次失败。再把失败蒸馏成一条 Dalio 式的可执行行为规则：
- title：不超过 20 字
- body："当…时，我将…"的形式，不超过 80 字，禁止空话套话
- misconception：一句话概括那个错误的心智模型本身（不超过 40 字），
  用来识别用户是不是在不同技能点上反复栽在同一类错误上

只输出严格 JSON：{{"title": "...", "body": "...", "misconception": "..."}}
不要输出 JSON 之外的任何文字。
"""


class Scribe:
    def __init__(self, provider: LLMProvider):
        self._provider = provider

    def distill(self, skill_title: str, gaps: list[str], reflection: str) -> tuple[str, str, str]:
        system = SYSTEM_PROMPT.format(
            skill_title=skill_title,
            gaps="、".join(gaps) if gaps else "（未记录具体缺口）",
            reflection=reflection,
        )
        messages: list[Message] = [
            {"role": "system", "content": system},
            {"role": "user", "content": reflection},
        ]
        logger.info("scribe.distill() calling provider=%s", self._provider.name)
        raw = complete_with_json_retry(self._provider, messages)
        try:
            data = json.loads(raw)
            return data["title"], data["body"], data["misconception"]
        except (json.JSONDecodeError, KeyError, TypeError):
            logger.warning("scribe.distill() failed to parse provider response, using fallback principle")
            return (
                f"{skill_title}：先讲机制再讲结论",
                "当我再次解释这个概念时，我将先说出它为什么成立，再说它是什么。",
                "以为记住结论就等于理解了机制",
            )
