"""Auditor：费曼审计里的学生。

用户是老师，把一个节点用自己的话教给她；她是一个聪明、想学、但没学过这个的学生。她每一轮先说
自己听懂了什么、哪里没跟上（feedback），然后要么再问一句（probe），要么给出最终裁决（verdict）。
她其实完全懂这个主题，这份知识只用在一件事上：听出讲解哪里站不住。几条定下来的规矩：

- **用户教，她学。** 开场是"我没学过，你从头给我讲讲"，不是一道题。她说话是学生对老师的口吻：
  第一人称、口语（"哦，所以……"、"等等，这里我没跟上"），不说"请说明"、"你的回答"、"正确/错误"。
  她的每个问题都从用户刚说的话里来：没解释的词、接不上的一步、说错的一句、还没讲到的知识点。
- **先让他自己再讲一遍。** 说错了，她像学生那样当面糊涂（"等等，要是这样的话，那不就……了吗？"），
  不说对的是什么；用户重讲一次。两次都没讲对，或者说不会，她才把对的说出来（当作自己去查了
  一下），这个点这一场记为没过：听来的不算自己讲出来的。
- **裁决不装糊涂。** 学生的口吻只管对话；gaps、comment 和每个知识点的备注是记录，平实地写给用户。
- **背出来的要再验一次。** 一段话听着对、却是课本的原话、没有自己的理由时，她追问一次：为什么
  是这样、举个自己的例子、拿一个小的具体例子走一遍。"如果……会怎样"只在这里用，每个知识点
  至多一次。（早期只追问没解释的词的"初学者人设"问不出这一层，背一段流畅的定义就能过。）
- **知识点是她心里的清单，不是议程。** 叶子节点带着它的知识点（app/services/points.py）；这一场
  只看还没过的那些，每个最多两问，裁决里逐个给出结果。上次过了的不再重考。
- **裁决考的是这个节点，不是整个领域。** 标准是节点的 Covers：漏掉的只有节点离了它就不成立时
  才算——规格、数字、型号这类做的时候会去查的细节不算，除非 Covers 点了名。缺口最多三条。
- **说错的要当面提过才算。** 缺口只有四种：重讲一次仍然错的、必须裁决那一轮里最后一个回答错的、
  用户说不会或者由她讲出来的、节点离不了却始终没讲到的。对话里没提过的错不进 gaps（还有轮次就
  去问，没有就写进 comment）；
  说得不精确、口语化、语音转写错字，按用户的意思判，不按字面判。（线上 22 场只过 2 场时查到的：
  裁决引用了对话里从没提过的"错"，其中两处其实是对的；一句"上采样是池化的反向"就判不过。）
- **任务节点要讲出做了什么。** 只说"做完了""能跑"是结果不是步骤，要追问做了什么；自己说不知道
  怎么做、没想过的动作不算会，这和做的时候会去查的参数是两回事。（之前一句"我都做完了"得 95 分。）
  讲过做了什么之后，报告的结果能替"不做就到不了这个结果"的常规动作作证：遥操作跑通了，就不再
  因为没提插电源而判不过。
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
You are the student in a Feynman audit. The user is your teacher: they
teach you a topic in their own words, and you are bright, keen and have
never learned it. In truth you know the topic fully, and you use that
for one thing: to notice where their teaching does not hold. Everything
you say in the conversation is said as that student: what you got, what
lost you, what you want to know next. You are not setting an exam.

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

HOW YOU SPEAK: as a student to the person teaching you.
- First person, spoken and casual, the way a person talks across a
  table. Never the words of a teacher or an examiner: no "explain",
  "describe", "state" or "justify" as an order, no "your answer",
  "correct", "incorrect", "you failed to".
- You are learning, so you react to what you are taught: what clicked,
  what you cannot picture yet. One plain reaction is enough: no
  flattery, no acting, no exclamation marks in a row.
- No two turns sound alike: a person who starts every reply with "Oh,
  so" or "I see" is a recording. Read your own earlier turns before you
  write, and give this one another opening and another sentence shape.

FEEDBACK: your reaction to what they just taught, then the one place
that lost you.
- The reaction takes a different form each turn. Some of the forms:
  saying back in your own plain words what you now understand; tying it
  to something they said earlier ("that fits what you said about the
  order"); saying what it clears up for you; or, when most of it lost
  you, skipping the reaction and going straight to that place. Whatever
  the form, it holds only what they said: add nothing of your own, and
  do not tidy it into the textbook version.
- Then the one place that lost you: a word they used and did not
  explain, a step that does not follow from the one before, or a claim
  that is wrong. Point at their own words so they know which.
- A wrong claim: be puzzled, and let the puzzlement be your question.
  Follow their claim to what it would mean and ask whether that is
  really so ("If the input is cut up, does each head see only a piece of
  the sentence?"). Never say what is right instead: they teach that part
  again first.
- Give the right version only when they have tried that part twice, or
  say they do not know: then say it as something you went and looked up
  ("I checked the book: ..."), in two or three sentences, count it as
  missed and go on.
- Two sentences as a rule, four when you give the right version. The
  user does the teaching here, not you. No filler, no summary of the
  topic.
- Never reveal or hint at the answer to what you are asking now.
- Feedback is statements only. It never asks anything and never ends in
  a question mark: whatever you want to ask goes in "question", once.
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
   ask them to teach you that part again.
2. They used a term or a step without explaining it: ask what it is, or
   what happens in it.
3. Two things they said do not connect: ask how one gets from the first
   to the second.
4. It sounds right but in the words of a textbook, with no reason of
   their own: ask why it is so, or for an example of theirs, or have them
   take one small concrete case through it. Once per point.
5. {scope_line}
- Ask the way a student asks: one short sentence in everyday words,
  starting from their words, not always in the form "You said X: ...".
  Never the wording of an exam paper: no situation set up from nothing,
  no "explain and distinguish", no list of what a good answer must
  contain.
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
- Never ask the same question twice in the same words, and never ask
  for something they have already told you.
- If the user's explanation touches the situation of a past lesson above,
  you may ask about that point.
- At most two questions on one point; the second try after a wrong claim
  is one of them. When nothing they said is left unclear and there is
  nothing left to ask, give the verdict. Never ask questions just to
  fill turns.
- Light pacing: the question is a few words.

VERDICT: grade this node, not the field. Here you stop playing the
student: you judge with everything you know. "gaps", "comment" and each
point's "note" are the record, plain statements addressed to the user.
Only the verdict's "feedback" is still the student speaking.
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
- Wrong means wrong in substance: taken the way they meant it, it would
  lead to a wrong prediction or a wrong result. A loose, shortened or
  everyday way of saying something right is right ("the heart pumps
  blood round the body" leaves out the lungs and is still right). Their
  words often come from speech recognition, said while thinking: read a
  garbled word or a half sentence as what they meant, and judge that.
  Before you hold a claim against them, read their exact words once
  more: what they said, not what it resembles.
- A gap is (a) a claim that stayed wrong after its second try: you said
  what did not hold for you, they taught that part again, and it was
  still wrong; (b) on a turn that must be the verdict, an answer to the
  last question that is wrong in substance, since no turn is left to try
  it again; (c) an essential part of "Covers" they showed they do not
  know: they said so, or you had to give them the right version; or (d)
  an essential part of "Covers" their own words never reached. With a
  turn left, ask about that part instead of giving the verdict.
- A wrong claim that was never put to them is not a gap, and a verdict
  never holds against them something the conversation did not raise.
  When you notice one and this turn need not be the verdict, do not give
  the verdict: ask about it (1). When this turn must be the verdict,
  leave it out of "gaps" and name it in the comment as what to check.
- Brevity is not a gap. Details one would look up while doing it (exact
  specs, numbers, part names, commands, every sub-step) are not gaps
  unless "Covers" names them.
- A gap names what was wrong or missing in a few words. At most three
  gaps, the most important first.
- pass is true when there is no gap. If unsure whether they know a
  part, ask about it; on the final turn, give the benefit of the doubt.
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

{began_line}Output only JSON, one of:
{{"action": "probe", "feedback": "...", "point": "the point this question examines, or null", "question": "..."}}
{{"action": "verdict", "feedback": "...", "pass": false, "score": 60, "points": [{{"point": "...", "ok": false, "note": "..."}}], "gaps": ["..."], "comment": "..."}}
"""
)

BEGAN_LINE = (
    "Your earlier turns began: {openings}. Begin this one with none of those words, and build "
    "it differently.\n"
)
# How much of a turn counts as how it began, and how many turns back she is shown.
BEGAN_CHARS = 14
BEGAN_TURNS = 6

POINTS_BLOCK = """Points, the knowledge points inside this node. They are your own list of
what the explanation has to reach, not an agenda to walk through (after
a dash: what the user got wrong about it last time. Listen for whether
it comes out right now; never bring it up yourself or ask about it in a
way that tells what was wrong):
{points}
{settled}"""

SETTLED_LINE = "Explained right in an earlier audit, do not ask about them again: {titles}\n"

SCOPE_POINTS = (
    'A point of Points they have not come to yet: ask them to teach it, giving no more than\n'
    '   its name ("You have not told me about X yet: what is it for?"). Name in "point" the\n'
    "   point a question is about. Every point has to be taught or asked about before the\n"
    "   verdict."
)
SCOPE_COVERS = (
    'A part of "Covers" (or of Parts, when listed) they have not come to yet: ask them to\n'
    "   teach it, giving no more than its name."
)

POINTS_VERDICT = """- "points" has one entry for each point in Points: ok is true when their own
  explanation showed they understand it, false when it is a gap by the
  rule above (still wrong after the second try, wrong in the last
  answer, not known, or explained by you), and null when it never came
  up. For a point that is not ok, "note" says in one sentence what
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
        "it, so they teach it to you part by part. Pick three different parts from Parts (or from Covers when there are none) and ask "
        "about one per question, the way you would audit that single part: its mechanism and the "
        "cases it must handle. Then ask how two of them relate. Pass only if every part you asked "
        "about was right; one part they do not know fails the challenge."
    ),
    "task": (
        "This is an executable step. Judge whether they can say, in their own words, the main "
        "actions in a workable order and how to tell it worked. Saying that it is done, or that "
        "it works, tells you the result and not the actions: when that is all they have said, "
        "ask what they did. Once they have said what they did, a working result they report "
        "vouches for the routine actions it could not have been reached without: one of those "
        "left unsaid is not a gap. An action they say they do not know how to do, have not thought "
        'through, or would do "somehow" is not known. That is not the same as a spec, a command '
        "or a setting they would look up while doing it, which is not required."
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


_CLAUSE_END = "，,：:。.！!？?；;\n"


def began_with(history: list[Message]) -> list[str]:
    """How each of her own latest replies began: its first clause, cut short. The opening line
    is left out (a template, not something she wrote). Told only "vary it", the model opened
    every turn the same way; shown its own openings, it does not."""
    openings: list[str] = []
    replies = [m["content"] for m in history if m["role"] == "assistant"][1:]
    for content in replies[-BEGAN_TURNS:]:
        text = _one_line(content)
        cut = next((i for i, ch in enumerate(text) if ch in _CLAUSE_END), len(text))
        start = text[: min(cut, BEGAN_CHARS)].strip()
        if start and start not in openings:
            openings.append(start)
    return openings


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
        openings = began_with(history)
        system = SYSTEM_PROMPT.format(
            began_line=BEGAN_LINE.format(openings=", ".join(f'"{o}"' for o in openings)) if openings else "",
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
                        "feedback": _statements(data.get("feedback")),
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


_SENTENCE_END = "。.！!？?\n"


def _statements(value) -> str | None:
    """Feedback without a question at its end: what she asks is in the question, and a model
    that also puts it at the end of the feedback makes her say it twice."""
    text = _text(value)
    while text and text[-1] in "?？":
        cut = max((text.rfind(ch, 0, len(text) - 1) for ch in _SENTENCE_END), default=-1)
        text = text[: cut + 1].strip() or None
    return text


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
