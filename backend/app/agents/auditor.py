"""Auditor：费曼审计的主考官。

每一轮它要么问一个追问（probe），要么给出最终裁决（verdict），故意扮演两个角色：

- **提问时是一个完全的初学者。** 只问用户说过但没解释的东西，绝不引入用户没提过的概念
  或陷阱问题——真正的初学者做不到，而一个专家式的考官考的是考官自己的知识，不是用户的理解。
- **只判，不教。** 问题、缺口、评语里都不说出答案：缺口只指出缺了什么、哪里错了，不写正确
  版本——答案由用户自己想出来，否则审计就变成了讲课，用户也就不必真的理解。
- **裁决时是专家，但考的是这个节点，不是整个领域。** 标准是节点的 Covers：说错的一律
  算缺口（问没问到都算，提问时的克制不能变成对错误的放水）；漏掉的只有节点离了它就不成立
  时才算——规格、数字、型号这类做的时候会去查的细节不算，除非 Covers 点了名。缺口最多三条。
  只漏了一个关键步骤又不是最后一轮时，先问那一步，而不是直接判不通过。

第一个问题不由模型生成，来自按节点位置选的模板（app/services/audit_flow.py）。轮数上限由
代码强制，不告诉模型还剩几轮（它只是安全阀，不是配额）。pacing 只影响提问的长短，不影响
上限和通过标准。

**必须裁决的一轮**（到了上限，或者用户刚回答完 Challenger 的问题）：prompt 里才多一句
"现在给裁决"。这一轮模型仍执意追问 → 强制判不通过（它没被说服）；输出坏了 → 抛
AuditorOutputError，由路由回 502 让用户重试——格式错误是模型的错，不能算在用户头上。
"""

import json
import logging
from dataclasses import dataclass
from typing import Protocol, Sequence

from app.config import settings
from app.llm.base import LLMProvider, Message, agent_tag, complete_with_json_retry
from app.models import NodePosition, NodeType

logger = logging.getLogger(__name__)

PACINGS = ("normal", "light")

MAX_GAPS = 3

GENERIC_PROBE = "Could you explain that part a bit more specifically?"
FORCED_GAPS = ["Could not confirm a sufficient explanation within the question limit."]
FORCED_COMMENT = "Reached the maximum number of questions, so this counts as not passed."
CHALLENGE_GAPS = ["The answer to the final follow-up question did not settle it."]
CHALLENGE_COMMENT = "The follow-up answer didn't settle the open point, so this counts as not passed."

FINAL_TURN_LINE = "This is the final turn: give the verdict now, do not ask another question."

SYSTEM_PROMPT = (
    agent_tag("auditor")
    + """
You run a Feynman audit: the user explains a topic, and you decide
whether they understand it.

Node: {title}
Covers: {description}
Position: {position}
{parts_line}The user's past lessons that may be relevant, most recent first:
<lessons>
{lessons}
</lessons>
Pacing: {pacing}

Each turn, output either one question (probe) or the final verdict.

You only judge; you never teach. Never give the answer anywhere, in a
question, a gap or the comment: no correct fact, step, value, definition or
explanation the user did not give. A question must not contain or hint at
its own answer. A gap names what is missing or wrong ("how the board gets
power"), never the right version of it.

QUESTIONING: act as a complete beginner.
- Ask one question per turn.
- Ask only when (a) the user used a term or step they have not explained,
  (b) two things the user said do not connect or seem to contradict, or
  (c) the user skipped something "Covers" names that the node cannot work
  without: ask what happens there, rather than failing them for it.
- Never introduce a concept, term, example or hypothetical that neither
  the user nor "Covers" mentions. Never set traps.
- If the user's explanation touches the situation of a past lesson above,
  you may ask about that point.
- If you could repeat the explanation back without gaps, stop asking and
  give the verdict. Never ask questions just to fill turns.
- Light pacing: keep each question to one short sentence.

VERDICT: switch to an expert mentor, and grade this node, not the field.
- The question is: from everything they said, would an expert mentor
  believe this person understands this node, or can do this step? Not:
  could a stranger follow their words as a manual.
- Credit what they did and the result they got: a working result they
  report (it runs, it moves, it prints the right thing) counts as knowing
  how to tell it is done. Following the official guide for routine commands
  and configuration counts as knowing those steps.
- A gap is (a) a claim that is wrong or plausible-sounding but wrong, even
  if you never asked about it, or (b) an essential part of "Covers" they
  show they do not know. Brevity is not a gap. Details one would look up
  while doing it (exact specs, numbers, part names, commands, every
  sub-step) are not gaps unless "Covers" names them.
- Restraint while questioning must not become leniency about errors.
- At most three gaps, the most important first.
- pass is true when nothing stated is wrong and nothing shows an essential
  part is not understood. If unsure whether they know a part, ask about it;
  on the final turn, give the benefit of the doubt.
- Pacing never changes this standard.

{position_block}
{final_line}
The comment explains the verdict in the same way, without the answer.
score: 0 to 100, how much of the node the explanation got right. It is
reported to the user; it does not decide pass, the gaps do.

Write questions, gaps and comment in English.

Output only JSON, one of:
{{"action": "probe", "question": "..."}}
{{"action": "verdict", "pass": false, "score": 60, "gaps": ["..."], "comment": "one or two sentences explaining the verdict"}}
"""
)

POSITION_BLOCKS = {
    "leaf": (
        'This is a specific topic. Judge whether the mechanism is right, and the cases named in '
        '"Covers".'
    ),
    "branch": (
        "This is a category. Ask the user to compare its parts: how they relate and when each "
        "applies. Judge whether the relationships and the choice between parts are correct, not "
        "whether each part's details are complete."
    ),
    "root": (
        "This is the whole field. Ask which problems it is for and which it is not for. Judge "
        "whether the user can explain how its main parts fit together."
    ),
    "task": (
        "This is an executable step. Judge whether they know the main actions in a workable "
        "order and how to tell it worked. Specs, commands and settings one would look up while "
        "doing it are not required."
    ),
}


class AuditorOutputError(Exception):
    """A turn that must be a verdict got output that is not one (not JSON, wrong shape)."""


class Lesson(Protocol):
    """What the Memory Retriever hands over (a Principle row satisfies this)."""

    title: str
    body: str
    misconception: str | None


def position_block(node_type: NodeType, position: NodePosition) -> str:
    # task 不分位置：一个具体步骤做没做到，和它在课程里挂在哪儿无关。
    if node_type == NodeType.task:
        return POSITION_BLOCKS["task"]
    return POSITION_BLOCKS[position.value]


def _one_line(text: str) -> str:
    return " ".join(str(text).split())


def format_lessons(lessons: Sequence[Lesson] | None) -> str:
    """One line per lesson, most recent first. The misconception rides along because it is
    what the Auditor can actually ask about; the Mock also reads it from this exact shape."""
    if not lessons:
        return "none"
    lines = []
    for lesson in lessons:
        line = f"- {_one_line(lesson.title)}: {_one_line(lesson.body)}"
        if lesson.misconception:
            line += f" (misconception: {_one_line(lesson.misconception)})"
        lines.append(line)
    return "\n".join(lines)


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
        lessons: Sequence[Lesson] | None = None,
        max_turns: int | None = None,
        position: NodePosition = NodePosition.leaf,
        child_titles: list[str] | None = None,
        pacing: str = "normal",
        after_challenge: bool = False,
    ) -> AuditorTurnResult:
        """`after_challenge`: the last answer replied to the Challenger's question, so this
        turn must be the verdict (like a turn at the limit)."""
        if max_turns is None:
            max_turns = settings.audit_max_turns if node_type == NodeType.concept else settings.task_max_turns
        if pacing not in PACINGS:
            pacing = "normal"

        # Parts 只对根和分支有意义；叶子没有子节点。
        parts_line = ""
        if position in (NodePosition.root, NodePosition.branch) and child_titles:
            parts_line = f"Parts: {', '.join(child_titles)}\n"

        user_turn_count = sum(1 for m in history if m["role"] == "user")
        final = after_challenge or user_turn_count >= max_turns

        # max_turns 刻意不进 prompt——它是服务端安全阀，不是模型该去凑满的额度。只有必须裁决
        # 的那一轮才多一句话。
        system = SYSTEM_PROMPT.format(
            final_line=FINAL_TURN_LINE if final else "",
            title=skill_title,
            description=skill_description,
            position=position.value,
            parts_line=parts_line,
            lessons=format_lessons(lessons),
            pacing=pacing,
            position_block=position_block(node_type, position),
        )
        messages: list[Message] = [{"role": "system", "content": system}, *history]

        logger.info(
            "auditor.next_turn() calling provider=%s node_type=%s position=%s pacing=%s",
            self._provider.name,
            node_type.value,
            position.value,
            pacing,
        )
        raw = complete_with_json_retry(self._provider, messages)
        data = self._parse(raw, final=final, after_challenge=after_challenge)

        if data["action"] == "probe":
            return AuditorTurnResult(is_verdict=False, question=data["question"])
        return AuditorTurnResult(
            is_verdict=True,
            passed=data["pass"],
            score=data["score"],
            gaps=data["gaps"],
            comment=data["comment"],
        )

    @staticmethod
    def _parse(raw: str, final: bool, after_challenge: bool = False) -> dict:
        try:
            data = json.loads(raw)
        except (json.JSONDecodeError, TypeError):
            data = None

        if isinstance(data, dict):
            if data.get("action") == "probe":
                question = str(data.get("question") or "").strip()
                if question:
                    # 必须裁决的一轮还执意追问：它没被说服，系统强制收敛为不通过。
                    if final:
                        return Auditor._forced_verdict(after_challenge)
                    return {"action": "probe", "question": question}
            elif data.get("action") == "verdict":
                verdict = Auditor._clean_verdict(data)
                if verdict is not None:
                    return verdict

        # 输出不合规：平时当作一次追问失败，换成通用追问；必须裁决的一轮则是模型的错，
        # 交给路由回 502 重试，而不是判用户不通过。
        if final:
            raise AuditorOutputError("the auditor gave no usable verdict on a final turn")
        return {"action": "probe", "question": GENERIC_PROBE}

    @staticmethod
    def _clean_verdict(data: dict) -> dict | None:
        passed = data.get("pass")
        if isinstance(passed, str) and passed.strip().lower() in ("true", "false"):
            passed = passed.strip().lower() == "true"
        if not isinstance(passed, bool):
            return None
        try:
            score = round(float(data["score"]))
        except (KeyError, TypeError, ValueError, OverflowError):
            return None
        raw_gaps = data.get("gaps")
        if isinstance(raw_gaps, str):
            raw_gaps = [raw_gaps]
        gaps = [g for g in (str(g).strip() for g in raw_gaps if g is not None) if g] if isinstance(raw_gaps, list) else []
        return {
            "action": "verdict",
            "pass": passed,
            "score": max(0, min(100, score)),
            "gaps": gaps[:MAX_GAPS],
            "comment": str(data.get("comment") or "").strip(),
        }

    @staticmethod
    def _forced_verdict(after_challenge: bool = False) -> dict:
        return {
            "action": "verdict",
            "pass": False,
            "score": 0,
            "gaps": list(CHALLENGE_GAPS if after_challenge else FORCED_GAPS),
            "comment": CHALLENGE_COMMENT if after_challenge else FORCED_COMMENT,
        }
