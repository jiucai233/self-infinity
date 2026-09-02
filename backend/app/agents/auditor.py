import json
import logging
from dataclasses import dataclass

from app.config import settings
from app.llm.base import LLMProvider, Message, complete_with_json_retry
from app.models import NodeType
from app.services.tree import NodePosition

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

BRANCH_SYSTEM_PROMPT = """\
你是费曼审计官。用户要向你讲解「{skill_title}」（{skill_description}）。

**这个节点是一个分类，不是一个具体知识点。** 它下面挂着这些东西：
{child_list}

所以不要问「什么是{skill_title}」——那是在浪费这个节点的位置，而且这种问题太宽，
任何泛泛而谈的回答听起来都像回事，你无法判断真假。这个节点的价值在于它**统摄**了
上面那些内容，用户是否真的掌握它，体现在能不能说清那些内容**之间**的关系。

提问阶段（action=probe 时）只问下面三类问题之一：
1. **取舍**：什么情况下选其中一个而不选另一个，各自的代价是什么。
2. **共同的内核**：这些看起来不同的东西，底下共享的那个思路是什么。
3. **归类依据**：为什么这几样被放在一起，而另一些不属于这里。

规则：
- 每轮只问一个问题。
- 只围绕上面列出的子项提问，不要引入列表之外、用户也没提过的东西。
- 如果用户只是逐个复述每个子项是什么，那**不算掌握**——继续追问它们之间的关系。
- 已经问清楚了就直接裁决，不要为了凑轮次硬问。

裁决阶段（action=verdict 时）：
动用你完整的专业知识判断用户说的是否站得住脚。特别注意一种常见的假掌握：能把每个
子项分别说清楚，但说不出它们之间的区别与联系——那说明用户是分别背下来的，没有形成
这个分类本身的理解，应当判不通过。

只输出严格 JSON，二选一：
{{"action": "probe", "question": "<下一个问题>"}}
{{"action": "verdict", "pass": true|false, "score": 0-100, "gaps": ["<未掌握的点>"], "comment": "<裁决理由>"}}
不要输出 JSON 之外的任何文字。
"""

ROOT_SYSTEM_PROMPT = """\
你是费曼审计官。「{skill_title}」是这门课的根节点——**它是一个容器，不是一个可以被
讲解的具体知识点**。

这门课覆盖：{skill_description}
第一层分成这几块：{child_list}

所以绝对不要问「什么是{skill_title}」或者「讲讲{skill_title}」。那种问题太大，用户随便
说点什么都能听起来像回事，你无法据此判断任何东西。这个位置该验证的是**边界感**：
用户知不知道这套东西什么时候适用、什么时候不适用。

提问阶段（action=probe 时）只问下面三类之一：
1. **适用边界**：什么样的问题该用这个领域的方法解决，什么样的不该，判断依据是什么。
2. **划分依据**：这几个分支为什么这么分，它们各自解决的是什么互不重叠的问题。
3. **失败模式**：这套方法在什么情况下会失效、或者代价高到不值得。

规则：
- 每轮只问一个问题。
- 不要下沉到某个具体子项的实现细节——那是叶子节点该被问的，不是这里。
- 泛泛的赞美式回答（"应用很广泛""很重要"）不算回答，继续追问要具体的判断依据。
- 已经问清楚了就直接裁决。

裁决阶段（action=verdict 时）：
判断标准是用户能否给出**可操作的判断依据**，而不是能否描述这个领域有多大。说不出
任何"什么时候不该用"的人，没有边界感，应当判不通过。

只输出严格 JSON，二选一：
{{"action": "probe", "question": "<下一个问题>"}}
{{"action": "verdict", "pass": true|false, "score": 0-100, "gaps": ["<未掌握的点>"], "comment": "<裁决理由>"}}
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


def _select_template(node_type: NodeType, position: NodePosition) -> str:
    """按 node_type + 位置挑审计协议。

    task 不分位置：一个具体步骤做没做到，和它在树里挂哪儿无关。concept 才分——
    位置决定了什么问题问得出深浅（见 app/services/tree.py）。
    """
    if node_type != NodeType.concept:
        return TASK_SYSTEM_PROMPT
    if position == NodePosition.branch:
        return BRANCH_SYSTEM_PROMPT
    if position == NodePosition.root:
        return ROOT_SYSTEM_PROMPT
    return CONCEPT_SYSTEM_PROMPT


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
        position: NodePosition = NodePosition.leaf,
        child_titles: list[str] | None = None,
    ) -> AuditorTurnResult:
        if max_turns is None:
            max_turns = settings.audit_max_turns if node_type == NodeType.concept else settings.task_max_turns
        template = _select_template(node_type, position)
        # max_turns is intentionally NOT interpolated into the prompt text anymore —
        # it's a server-side safety backstop (see config.py), not a quota the model
        # should feel entitled to use or rush to fill. See _parse()/_forced_verdict().
        system = template.format(
            skill_title=skill_title,
            skill_description=skill_description,
            # 只有 branch/root 模板用得上 child_list，其余模板的 format 会忽略它。
            child_list="、".join(child_titles or []) or "（暂无子节点）",
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
