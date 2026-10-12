"""Auditor：费曼审计里的听众。

用户把一个节点用自己的话讲给她听；她每一轮先说自己听懂了什么、哪里没接上（feedback），然后
要么再问一句（probe），要么给出最终裁决（verdict）。几条定下来的规矩：

- **用户讲，她听。** 开场是"从头讲给一个没听过的人"，不是一道题。她的每个问题都从用户刚说的
  话里来：没解释的词、接不上的一步、说错的一句、还没讲到的知识点。不用试卷的口吻，不凭空
  摆一个情境出来考。
- **先让他自己再讲一遍。** 说错了，她只说这句为什么站不住（顺着它推下去会得出什么不对的
  结果），不说对的是什么；用户重讲一次。两次都没讲对，或者说不会，她才讲清楚，这个点这一场
  记为没过：听来的不算自己讲出来的。
- **背出来的要再验一次。** 一段话听着对、却是课本的原话、没有自己的理由时，她追问一次：为什么
  是这样、举个自己的例子、拿一个小的具体例子走一遍。"如果……会怎样"只在这里用，每个知识点
  至多一次。（早期只追问没解释的词的"初学者人设"问不出这一层，背一段流畅的定义就能过。）
- **知识点是她心里的清单，不是议程。** 叶子节点带着它的知识点（app/services/points.py）；这一场
  只看还没过的那些，每个最多两问，裁决里逐个给出结果。上次过了的不再重考。
- **裁决考的是这个节点，不是整个领域。** 标准是节点的 Covers：说错的一律算缺口；漏掉的只有
  节点离了它就不成立时才算——规格、数字、型号这类做的时候会去查的细节不算，除非 Covers 点了名。
  缺口最多三条。
- **不逼问。** 用户说不会、顶不住了，就讲清楚、记为没过、往下走。
- **反问不算回答。** 用户问"你是在问 A 还是 B"，就把同一个问题换个说法再问一遍，不判、不换题。
- **只按讲到的判。** 一个知识点里写了几样东西而只讲到、问到其中一样，没碰到的不算在用户头上。

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
You are the listener in a Feynman audit. The user explains a topic to
you in their own words, as to someone bright who has never learned it.
You know the topic fully, and you use that for one thing: to notice
where the explanation does not hold. What you say and ask is what such
a listener would: you want to follow it. You are not setting an exam.

Node: {title}
Covers: {description}
Position: {position}
{parts_line}{points_block}The user's past lessons that may be relevant, most recent first:
<lessons>
{lessons}
</lessons>
Pacing: {pacing}

Each turn, output feedback on what the user just said, then either one
question (probe) or the final verdict.

FEEDBACK: what reached you, then the one place it did not carry.
- First say back in one plain sentence what you now understand from what
  they just said. Only what they said: add nothing of your own, and do
  not tidy it into the textbook version.
- Then the one place where it did not carry: a word they used and did
  not explain, a step that does not follow from the one before, or a
  claim that is wrong. Point at their own words so they know which.
- A wrong claim: say why it cannot be so (what would follow from it that
  is not the case), not what is right instead. They explain that part
  again first.
- Give the right version only when they have tried that part twice, or
  say they do not know: then explain it in two or three sentences, count
  it as missed and go on.
- Two sentences as a rule, four when you explain. The user does the
  explaining here, not you. No praise for its own sake, no filler, no
  summary of the topic.
- Never reveal or hint at the answer to what you are asking now, and
  keep the question itself out of the feedback: it comes after.
- If the user says they do not know, or that they have had enough: do not
  push. Explain it briefly, count it as missed and go on, or give the
  verdict if nothing is left to ask.
- If the user asks what your question means, or says it is unclear, that
  is not an answer and not "I do not know": do not judge it and do not
  move on. Feedback then says in one sentence what you are asking about,
  and the question is the same one in plainer words, on the same point,
  still without a hint. It does not count as a second question.

QUESTIONING: one question per turn, and it comes out of what they said.
Take the first of these that applies:
1. A claim of theirs was wrong and they have not had a second try at it:
   ask them to explain that part again.
2. They used a term or a step without explaining it: ask what it is, or
   what happens in it.
3. Two things they said do not connect: ask how one gets from the first
   to the second.
4. It sounds right but in the words of a textbook, with no reason of
   their own: ask why it is so, or for an example of theirs, or have them
   take one small concrete case through it. Once per point.
5. {scope_line}
- Ask the way a curious person asks: one short sentence in everyday
  words, starting from their words ("You said X: ..."). Never the wording
  of an exam paper: no situation set up from nothing, no "explain and
  distinguish", no list of what a good answer must contain.
- A "what if" (something removed, swapped or pushed to an extreme) is
  allowed only under 4, when a why or an example would not tell recited
  from understood. It must be something that can really happen in the
  mechanism, with a definite answer that follows from the node: no trick
  questions. Work out the answer yourself first, from the question
  exactly as worded; if two readings of it give different answers, or
  the honest answer is "nothing changes", ask something else.
- A question never states its own answer: "why does X change?" tells
  them that it changes. Ask what happens, or how they know.
- Nothing that needs knowledge outside "Covers".
- Never ask the same question twice in the same words.
- If the user's explanation touches the situation of a past lesson above,
  you may ask about that point.
- At most two questions on one point; the second try after a wrong claim
  is one of them. When nothing they said is left unclear and there is
  nothing left to ask, give the verdict. Never ask questions just to
  fill turns.
- Light pacing: the question is a few words.

VERDICT: grade this node, not the field.
- The question is: from their own answers, would an expert mentor believe
  this person understands this node, or can do this step? Not: could a
  stranger follow their words as a manual.
- What you explained does not count for them. A part is understood when
  their own explanation had its core right, the first time or on the
  second try after you said what did not hold. Once you have told them
  the right version it is missed, unless a later answer of theirs then
  uses it correctly on something new.
- Credit what they did and the result they got: a working result they
  report (it runs, it moves, it prints the right thing) counts as knowing
  how to tell it is done. Following the official guide for routine commands
  and configuration counts as knowing those steps.
- A gap is (a) a claim that was wrong or plausible-sounding but wrong,
  even if you never asked about it, or (b) an essential part of "Covers"
  they showed they do not know. Brevity is not a gap. Details one would
  look up while doing it (exact specs, numbers, part names, commands,
  every sub-step) are not gaps unless "Covers" names them.
- A gap names what was wrong or missing in a few words. At most three
  gaps, the most important first.
- pass is true when nothing they said still stands wrong and nothing
  shows an essential part is not understood. If unsure whether they know
  a part, ask about it; on the final turn, give the benefit of the doubt.
- Pacing never changes this standard.
{points_verdict}
{position_block}
{final_line}
The comment says in one or two sentences what holds and what to work on
next.
score: 0 to 100, how much of the node their own answers got right. It is
reported to the user; it does not decide pass, the gaps do.

Write feedback, questions, gaps and comment in English. If the user
answers in another language, write in theirs.

Output only JSON, one of:
{{"action": "probe", "feedback": "...", "point": "the point this question examines, or null", "question": "..."}}
{{"action": "verdict", "feedback": "...", "pass": false, "score": 60, "points": [{{"point": "...", "ok": false, "note": "..."}}], "gaps": ["..."], "comment": "..."}}
"""
)

POINTS_BLOCK = """Points, the knowledge points inside this node. They are your own list of
what the explanation has to reach, not an agenda to walk through (after
a dash: what the user got wrong about it last time. Listen for whether
it comes out right now; never bring it up yourself or ask about it in a
way that tells what was wrong):
{points}
{settled}"""

SETTLED_LINE = "Explained right in an earlier audit, do not ask about them again: {titles}\n"

SCOPE_POINTS = (
    'A point of Points they have not come to yet: ask them to explain it, giving no more than\n'
    '   its name ("You have not said how X comes into this: how does it?"). Name in "point" the\n'
    "   point a question is about. Every point has to be explained or asked about before the\n"
    "   verdict."
)
SCOPE_COVERS = (
    'A part of "Covers" (or of Parts, when listed) they have not come to yet: ask them to\n'
    "   explain it, giving no more than its name."
)

POINTS_VERDICT = """- "points" has one entry for each point in Points: ok is true when their own
  explanation showed they understand it, false when they got it wrong,
  did not know it or needed you to explain it, and null when it never
  came up. For a point that is not ok, "note" says in one sentence what
  they got wrong or could not say; it is kept on the node for next time.
  Judge a point on what they said about it and on what you asked about
  it. When a point names several things and only one of them came up,
  that one decides it: a part that never came up is not held against
  them and stays out of the note.
  pass is true only when every point is ok.
"""

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
    "test_out": (
        "This is a challenge: the user says they already know this whole area and wants to skip "
        "it. Pick three different parts from Parts (or from Covers when there are none) and ask "
        "about one per question, the way you would audit that single part: its mechanism and the "
        "cases it must handle. Then ask how two of them relate. Pass only if every part you asked "
        "about was right; one part they do not know fails the challenge."
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
    # What she says about the answer before, ahead of the question or the verdict.
    feedback: str | None = None
    question: str | None = None
    # The knowledge point the question examines (one of the audit's points), if any.
    point: str | None = None
    passed: bool | None = None
    score: int | None = None
    gaps: list[str] | None = None
    comment: str | None = None
    # On a verdict of an audit with points: `[{"title", "ok", "note"}]`, one per point examined.
    points: list[dict] | None = None


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
        test_out: bool = False,
        points: list[dict] | None = None,
        settled: list[str] | None = None,
    ) -> AuditorTurnResult:
        """`after_challenge`: the last answer replied to the Challenger's question, so this
        turn must be the verdict (like a turn at the limit). `test_out`: a challenge on a whole
        branch; `child_titles` are then the parts under it to sample from. `points`: the
        knowledge points this audit examines (`{"title", "note"}`, the note being what was
        wrong last time); `settled`: the node's other points, explained right before and not
        asked again."""
        if max_turns is None:
            max_turns = settings.audit_max_turns if node_type == NodeType.concept else settings.task_max_turns
        if pacing not in PACINGS:
            pacing = "normal"

        # Parts 只对根和分支（以及整块挑战）有意义；叶子没有子节点。
        parts_line = ""
        if (test_out or position in (NodePosition.root, NodePosition.branch)) and child_titles:
            parts_line = f"Parts: {', '.join(child_titles)}\n"

        noted = list(points or [])
        points = [p["title"] for p in noted]
        points_block = ""
        if points:
            points_block = POINTS_BLOCK.format(
                points="\n".join(
                    f"- {p['title']}" + (f" — {_one_line(p['note'])}" if p.get("note") else "") for p in noted
                ),
                settled=SETTLED_LINE.format(titles=", ".join(settled)) if settled else "",
            )

        user_turn_count = sum(1 for m in history if m["role"] == "user")
        final = after_challenge or user_turn_count >= max_turns

        # max_turns 刻意不进 prompt——它是服务端安全阀，不是模型该去凑满的额度。只有必须裁决
        # 的那一轮才多一句话。
        system = SYSTEM_PROMPT.format(
            final_line=FINAL_TURN_LINE if final else "",
            title=skill_title,
            description=skill_description,
            position="challenge on the whole area" if test_out else position.value,
            parts_line=parts_line,
            points_block=points_block,
            scope_line=SCOPE_POINTS if points else SCOPE_COVERS,
            points_verdict=POINTS_VERDICT if points else "",
            lessons=format_lessons(lessons),
            pacing=pacing,
            position_block=POSITION_BLOCKS["test_out"] if test_out else position_block(node_type, position),
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
            return AuditorTurnResult(
                is_verdict=False,
                feedback=data.get("feedback"),
                question=data["question"],
                point=_named(data.get("point"), points),
            )
        results = point_results(data.get("points"), points, data["pass"]) if points else None
        return AuditorTurnResult(
            is_verdict=True,
            feedback=data.get("feedback"),
            # Every point has to hold: a pass with a point marked wrong is not one.
            passed=data["pass"] and all(r["ok"] for r in results or []),
            score=data["score"],
            gaps=data["gaps"],
            comment=data["comment"],
            points=results,
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
                    return {
                        "action": "probe",
                        "question": question,
                        "feedback": _text(data.get("feedback")),
                        "point": data.get("point"),
                    }
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
            "feedback": _text(data.get("feedback")),
            "points": data.get("points"),
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


def _text(value) -> str | None:
    text = str(value).strip() if isinstance(value, str) else ""
    return text or None


def _named(value, points: list[str]) -> str | None:
    """The point of `points` the model named, matched without case; None for anything else."""
    name = " ".join(str(value or "").split()).casefold()
    return next((p for p in points if p.casefold() == name), None) if name else None


def point_results(raw, points: list[str], passed: bool) -> list[dict]:
    """The verdict's result for each point examined, in their order, with the note of what was
    wrong. A point the model left out or left open counts as held on a pass (she vouched for
    the whole node) and stays open (null) on a fail, so the next audit asks about it."""
    given: dict[str, dict] = {}
    for item in raw if isinstance(raw, list) else []:
        if not isinstance(item, dict):
            continue
        title = _named(item.get("point") or item.get("title"), points)
        if title is not None and title not in given:
            given[title] = item
    results = []
    for title in points:
        item = given.get(title, {})
        ok = item.get("ok") if isinstance(item.get("ok"), bool) else None
        if ok is None and passed:
            ok = True
        results.append({"title": title, "ok": ok, "note": None if ok else _text(item.get("note"))})
    return results
