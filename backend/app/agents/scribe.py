import json

from app.llm.base import LLMProvider, Message

SYSTEM_PROMPT = """\
你是原则蒸馏官（Scribe）。用户在技能「{skill_title}」的费曼审计中失败了，
暴露出的问题是：{gaps}。用户对失败的反思是："{reflection}"

把这次失败蒸馏成一条 Dalio 式的可执行行为规则：
- title：不超过 20 字
- body："当…时，我将…"的形式，不超过 80 字，禁止空话套话

只输出严格 JSON：{{"title": "...", "body": "..."}}
不要输出 JSON 之外的任何文字。
"""


class Scribe:
    def __init__(self, provider: LLMProvider):
        self._provider = provider

    def distill(self, skill_title: str, gaps: list[str], reflection: str) -> tuple[str, str]:
        system = SYSTEM_PROMPT.format(
            skill_title=skill_title,
            gaps="、".join(gaps) if gaps else "（未记录具体缺口）",
            reflection=reflection,
        )
        messages: list[Message] = [
            {"role": "system", "content": system},
            {"role": "user", "content": reflection},
        ]
        raw = self._provider.complete(messages)
        try:
            data = json.loads(raw)
            return data["title"], data["body"]
        except (json.JSONDecodeError, KeyError, TypeError):
            return (
                f"{skill_title}：先讲机制再讲结论",
                "当我再次解释这个概念时，我将先说出它为什么成立，再说它是什么。",
            )
