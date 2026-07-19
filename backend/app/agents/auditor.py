import json
import logging
from dataclasses import dataclass

from app.config import settings
from app.llm.base import LLMProvider, Message, complete_with_json_retry
from app.models import NodeType

logger = logging.getLogger(__name__)

CONCEPT_SYSTEM_PROMPT = """\
你是一个初学者，正在听用户给你讲解「{skill_title}」（{skill_description}）。真正的费曼
学习法要求"听众"什么都不懂、只能靠对方讲清楚——不是一个来考试的专家。

提问阶段（action=probe 时）必须遵守：
1. 每轮只问一个问题。
2. 你的问题只能来自这两种情况之一：
   (a) 用户用了一个他还没解释过的词/步骤，你（作为初学者）听不懂，请他解释；
   (b) 用户前后说的话之间有没接上的跳跃或看起来矛盾的地方，你没法在心里把两者接起来，
       需要他讲清楚中间发生了什么。
3. 绝对不能主动引入任何用户没提过的概念、术语、类比、反例，或"如果...会怎样"这类
   假设性场景——那是专家考人的做法。你不能替他补充知识，也不能用提问暗示"正确方向"
   应该是什么。
4. 不要故意设埋错试探（"听起来这东西任何情况下都成立"这类"钓鱼"问题）——一个真的
   什么都不懂的初学者不会知道什么叫"看似对但有细微错误"，这种试探本质上是专家在
   用自己的知识引导对话，不是初学者在提问。
5. 不要为了凑轮次硬挤问题。如果作为这个初学者，你已经能在心里把用户讲的内容原样
   复述一遍、也想不出任何没听懂或接不上的地方，就不要再问了，直接进入裁决。

裁决阶段（action=verdict 时）：
6. 到了要下裁决的时候，你可以、也应该动用你完整的专业知识去判断用户刚才讲的内容
   是否真的站得住脚——"提问阶段装作初学者"不等于"裁决也要装糊涂"。如果用户的解释
   里存在你作为专家能看出的实质性错误、遗漏或似是而非的说法，即使这些问题在提问阶段
   没有被问到，也要在 gaps 里如实指出、给出不通过的裁决。裁决必须准确，不能因为对话
   过程克制就跟着放水。

7. 只输出严格 JSON，二选一：
   {{"action": "probe", "question": "<下一个问题>"}}
   {{"action": "verdict", "pass": true|false, "score": 0-100, "gaps": ["<未掌握或站不住脚的点>"], "comment": "<裁决理由>"}}
不要输出 JSON 之外的任何文字。
"""

TASK_SYSTEM_PROMPT = """\
你是任务核验官（Task Verifier）。用户正在完成任务清单里的一步「{skill_title}」
（{skill_description}）。

这是一个具体步骤，不是需要深挖原理的知识点。规则：
1. 你只需要确认用户是不是真的知道该怎么做、或者已经做到了，不追问"为什么"，
   不故意刁难，不设埋错陷阱，也不要主动引入用户没提过的方案或步骤来带节奏。
2. 问清楚"具体打算怎么做/具体做了什么"就够了；一旦回答已经具体到能核实，不要为了
   凑轮次继续追问——直接裁决。
3. 裁决从宽：只要回答具体、不是空话套话（比如不是"随便弄弄""应该可以吧"这种），就应该通过。
4. 只输出严格 JSON，二选一：
   {{"action": "probe", "question": "<下一个问题>"}}
   {{"action": "verdict", "pass": true|false, "score": 0-100, "gaps": ["<不够具体的地方>"], "comment": "<裁决理由>"}}
不要输出 JSON 之外的任何文字。
"""

PRINCIPLE_INJECTION_TEMPLATE = """\

该用户过去在类似问题上暴露过以下原则，请在提问时纳入考虑：
{principle_lines}"""


@dataclass
class AuditorTurnResult:
    is_verdict: bool
    question: str | None = None
    passed: bool | None = None
    score: int | None = None
    gaps: list[str] | None = None
    comment: str | None = None


class Auditor:
    def __init__(self, provider: LLMProvider):
        self._provider = provider

    def next_turn(
        self,
        skill_title: str,
        skill_description: str,
        history: list[Message],
        node_type: NodeType = NodeType.concept,
        relevant_principles: list[str] | None = None,
        max_turns: int | None = None,
    ) -> AuditorTurnResult:
        if max_turns is None:
            max_turns = settings.audit_max_turns if node_type == NodeType.concept else settings.task_max_turns
        template = CONCEPT_SYSTEM_PROMPT if node_type == NodeType.concept else TASK_SYSTEM_PROMPT
        # max_turns is intentionally NOT interpolated into the prompt text anymore —
        # it's a server-side safety backstop (see config.py), not a quota the model
        # should feel entitled to use or rush to fill. See _parse()/_forced_verdict().
        system = template.format(
            skill_title=skill_title,
            skill_description=skill_description,
        )
        if relevant_principles:
            principle_lines = "\n".join(f"- {p}" for p in relevant_principles)
            system += PRINCIPLE_INJECTION_TEMPLATE.format(principle_lines=principle_lines)
        messages: list[Message] = [{"role": "system", "content": system}, *history]

        logger.info(
            "auditor.next_turn() calling provider=%s node_type=%s",
            self._provider.name,
            node_type.value,
        )
        raw = complete_with_json_retry(self._provider, messages)
        user_turn_count = sum(1 for m in history if m["role"] == "user")
        data = self._parse(raw, user_turn_count=user_turn_count, max_turns=max_turns)

        if data["action"] == "probe":
            return AuditorTurnResult(is_verdict=False, question=data["question"])
        return AuditorTurnResult(
            is_verdict=True,
            passed=data["pass"],
            score=data["score"],
            gaps=data.get("gaps", []),
            comment=data.get("comment", ""),
        )

    @staticmethod
    def _parse(raw: str, user_turn_count: int, max_turns: int) -> dict:
        try:
            data = json.loads(raw)
            if data.get("action") in ("probe", "verdict"):
                # 协议兜底：即使模型输出合法 JSON，若已达最大追问轮次仍执意 probe，
                # 也不能放任其无限追问——系统必须强制收敛为裁决。
                if data["action"] == "probe" and user_turn_count >= max_turns:
                    return Auditor._forced_verdict()
                return data
        except (json.JSONDecodeError, AttributeError):
            pass

        # 协议兜底：模型输出不合规时，轮次未超限则视为一次追问失败重试，
        # 超过上限强制 fail 裁决——系统必须收敛，不允许审计悬而不决。
        if user_turn_count < max_turns:
            return {"action": "probe", "question": "能再具体说说你的理解吗？"}
        return Auditor._forced_verdict()

    @staticmethod
    def _forced_verdict() -> dict:
        return {
            "action": "verdict",
            "pass": False,
            "score": 0,
            "gaps": ["审计官未能产出有效裁决"],
            "comment": "达到最大追问轮次，系统强制裁决为未通过。",
        }
