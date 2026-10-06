"""确定性的 LLM 替身：不调用任何外部模型，用于离线演示与 CI 测试。

行为严格按 docs/api-contract.md 第 4 节的演示脚本，Flutter 的 FakeApiClient 也遵循同一份，
所以有没有后端，界面表现一致。脚本只认字面规则（长度、关键词），真 provider 判的是语义——
这是有意的妥协：离线可测，但不能拿 Mock 的准确率说明任何关于模型的事。

路由靠 system prompt 第一行的 "[agent: xxx]"（见 app/llm/base.py）。
"""

import json
import logging
import re
import time

from app.llm.base import JSON_RETRY_NOTICE, Message, agent_of

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------- demo script constants (English)

_STATS_QUESTION = "Do you mean high-school probability and statistics, or university-level statistics?"

_DEFAULT_PROBE = "Pick the most important term in your explanation and tell me what it means and why it matters."
_LESSON_PROBE = "You once thought “{misconception}”. How is this explanation different?"
_PASS_MIN_CHARS = 80
# The latest answer fails the script if it admits not knowing. "모르" is the Korean fallback
# (kept so Korean transcripts still work).
_FAIL_MARKERS = ("don't know", "not sure", "모르")
_PASS_COMMENT = "You explained the core idea and why it holds."
_FAIL_SCORE = 45
_FAIL_GAPS = [
    "You stated the definition but not why it works.",
    "You didn't cover the exceptions.",
]
_FAIL_COMMENT = "The answer stops at the conclusion and lacks reasons."

_CHALLENGE_BELOW_CHARS = 160
_CHALLENGE_QUESTION = "Before I pass this: give one case where this idea does not hold, and explain why."

_LINK_REASON = "Same concept, similar misconception"

_SYLLABUS_COURSE = "High School Mathematics Curriculum (Ministry of Education)"
_SYLLABUS_OUTLINE = [
    "Algebra",
    "Quadratic Equations",
    "Sequences",
    "Functions",
    "Linear and Quadratic Functions",
    "Calculus",
    "Limits of Sequences",
    "Derivatives",
]

# slug, title, description, parents (first = main parent)
_MATH_NODES = [
    (
        "high-school-math",
        "High School Math",
        "The whole of high school math: which problems call for algebra, functions or calculus.",
        [],
    ),
    ("algebra", "Algebra", "Expressions and equations; groups quadratic equations and sequences.", ["high-school-math"]),
    (
        "functions",
        "Functions",
        "Relationships between variables; groups linear and quadratic functions.",
        ["high-school-math"],
    ),
    (
        "calculus",
        "Calculus",
        "Limits and rates of change; groups limits of sequences and derivatives.",
        ["high-school-math"],
    ),
    (
        "quadratic-equation",
        "Quadratic Equations",
        "Use the discriminant to tell the kind of roots (two distinct real, one repeated, two complex) "
        "and explain how roots relate to coefficients.",
        ["algebra"],
    ),
    (
        "discriminant",
        "Discriminant",
        "Use the sign of the discriminant D = b² − 4ac to tell how many roots a quadratic equation has and of what kind.",
        ["quadratic-equation"],
    ),
    (
        "root-coefficient",
        "Roots and Coefficients",
        "Find the sum and product of the two roots from the coefficients without solving the equation.",
        ["quadratic-equation"],
    ),
    ("sequences", "Sequences", "Find the general term and the sum of arithmetic and geometric sequences.", ["algebra"]),
    (
        "linear-function",
        "Linear Functions",
        "Draw and interpret the graph of a linear function from its slope and y-intercept.",
        ["functions"],
    ),
    (
        "quadratic-function",
        "Quadratic Functions",
        "Find the vertex, axis, x-intercepts and the maximum or minimum of a quadratic function's graph.",
        ["functions"],
    ),
    (
        "sequence-limit",
        "Limits of Sequences",
        "Explain when a sequence converges and how to find its limit.",
        ["calculus", "sequences"],
    ),
    (
        "derivative",
        "Derivatives",
        "Define the instantaneous rate of change at a point as a limit and compute it.",
        ["calculus"],
    ),
]
_MATH_REQUIRES = [
    ("quadratic-equation", "quadratic-function", "The x-intercepts of a quadratic function are the roots of a quadratic equation."),
    ("linear-function", "quadratic-function", "You need the graph of a linear function first."),
    ("sequence-limit", "derivative", "The derivative is defined as a limit."),
]
_ROOT_TITLE_CHARS = 24

# Generic topic: a root, 3 branches and 6 leaves.
_GENERIC_BRANCHES = [("core-concepts", "Core Concepts"), ("main-methods", "Key Methods"), ("applications", "Applications")]

# ---------------------------------------------------------------- parsing helpers

_LESSONS_BLOCK_RE = re.compile(r"<lessons>\n(.*?)\n</lessons>", re.S)
_LESSON_LINE_RE = re.compile(r"^- .*\(misconception: (.*)\)\s*$")
_RESULT_LINE_RE = re.compile(r"^\[(\d+)\] ")
_LINK_PRINCIPLE_RE = re.compile(r"^\[(\d+)\] P\b")
_NODE_LINE_RE = re.compile(r"^Node: (.*)$", re.M)
_TOPIC_BLOCK_RE = re.compile(r"Topic:(.*?)\nResults:", re.S)


def _system(messages: list[Message]) -> str:
    return next((m["content"] for m in messages if m["role"] == "system"), "")


def _first_user(messages: list[Message]) -> str:
    return next((m["content"] for m in messages if m["role"] == "user"), "")


def _user_turns(messages: list[Message]) -> list[str]:
    # complete_with_json_retry 重试时会追加一条纠错用的 user 消息，那不是用户的话。
    return [m["content"] for m in messages if m["role"] == "user" and m["content"] != JSON_RETRY_NOTICE]


def _dump(data: dict) -> str:
    return json.dumps(data, ensure_ascii=False)


# ---------------------------------------------------------------- 各子 agent 的脚本


def _is_math(topic: str) -> bool:
    # "수학" (Korean for math) is still accepted as a fallback.
    return "math" in topic.casefold() or "수학" in topic


def _clarify(messages: list[Message]) -> str:
    topic = _first_user(messages)
    # "통계" (Korean for statistics) is still accepted as a fallback.
    if "statistics" in topic.casefold() or "통계" in topic:
        return _dump({"needs_clarification": True, "questions": [_STATS_QUESTION]})
    return _dump({"needs_clarification": False, "questions": []})


def _syllabus(messages: list[Message]) -> str:
    system = _system(messages)
    topic_match = _TOPIC_BLOCK_RE.search(system)
    topic = topic_match.group(1) if topic_match else ""
    first_index = next(
        (int(m.group(1)) for line in system.splitlines() if (m := _RESULT_LINE_RE.match(line.strip()))),
        None,
    )
    if not _is_math(topic) or first_index is None:
        return _dump({"found": False})
    return _dump(
        {"found": True, "index": first_index, "course": _SYLLABUS_COURSE, "outline": _SYLLABUS_OUTLINE}
    )


def _plan(messages: list[Message]) -> str:
    topic = _first_user(messages).strip()
    if _is_math(topic):
        nodes = [
            {"slug": slug, "title": title, "description": desc, "parents": parents, "node_type": "concept"}
            for slug, title, desc, parents in _MATH_NODES
        ]
        requires = [{"from": a, "to": b, "reason": reason} for a, b, reason in _MATH_REQUIRES]
        return _dump({"nodes": nodes, "requires": requires})

    root_title = (topic.splitlines()[0].strip() if topic else "")[:_ROOT_TITLE_CHARS].strip() or "New Topic"
    nodes = [
        {
            "slug": "root",
            "title": root_title,
            "description": f"Everything about “{root_title}”, grouping the three areas below.",
            "parents": [],
            "node_type": "concept",
        }
    ]
    for slug, title in _GENERIC_BRANCHES:
        nodes.append(
            {
                "slug": slug,
                "title": title,
                "description": f"The {title.lower()} of “{root_title}”, grouped as one category.",
                "parents": ["root"],
                "node_type": "concept",
            }
        )
    for slug, title in _GENERIC_BRANCHES:
        for i in (1, 2):
            nodes.append(
                {
                    "slug": f"{slug}-{i}",
                    "title": f"{title} {i}",
                    "description": f"Explain the definition of {title} {i} and why it holds.",
                    "parents": [slug],
                    "node_type": "concept",
                }
            )
    requires = [
        {
            "from": "core-concepts-1",
            "to": "main-methods-1",
            "reason": "You need the core concepts before you can follow the key methods.",
        },
        {
            "from": "main-methods-1",
            "to": "applications-1",
            "reason": "You need the key methods before you can apply them.",
        },
    ]
    return _dump({"nodes": nodes, "requires": requires})


def _audit(messages: list[Message]) -> str:
    user_turns = _user_turns(messages)
    if len(user_turns) <= 1:
        lessons = _LESSONS_BLOCK_RE.search(_system(messages))
        if lessons:
            for line in lessons.group(1).splitlines():
                match = _LESSON_LINE_RE.match(line.strip())
                if match:
                    # Memory Retriever 最近的在前，取第一条带 misconception 的。
                    return _dump({"action": "probe", "question": _LESSON_PROBE.format(misconception=match.group(1))})
        return _dump({"action": "probe", "question": _DEFAULT_PROBE})

    n = len("".join(user_turns))
    latest = user_turns[-1].replace("’", "'").casefold()
    if n >= _PASS_MIN_CHARS and not any(marker in latest for marker in _FAIL_MARKERS):
        return _dump(
            {
                "action": "verdict",
                "pass": True,
                "score": min(95, 70 + n // 10),
                "gaps": [],
                "comment": _PASS_COMMENT,
            }
        )
    return _dump(
        {"action": "verdict", "pass": False, "score": _FAIL_SCORE, "gaps": _FAIL_GAPS, "comment": _FAIL_COMMENT}
    )


def _challenge(messages: list[Message]) -> str:
    n = len("".join(_user_turns(messages)))
    if n < _CHALLENGE_BELOW_CHARS:
        return _dump({"action": "overturn", "question": _CHALLENGE_QUESTION, "reason": "mock: the answer is short"})
    return _dump({"action": "uphold", "reason": "mock: the answer is long enough"})


def _record(messages: list[Message]) -> str:
    match = _NODE_LINE_RE.search(_system(messages))
    skill_title = match.group(1).strip() if match else ""
    reflection = _first_user(messages).strip()
    return _dump(
        {
            "title": f"Revisit “{skill_title}”"[:40],
            "body": f"When I explain “{skill_title}”, I give the reason before the conclusion."[:120],
            "misconception": reflection[:60],
        }
    )


def _link(messages: list[Message]) -> str:
    # 候选按"最近的在前"编号，所以第一个 P 就是最近的另一条原则。
    for line in _system(messages).splitlines():
        match = _LINK_PRINCIPLE_RE.match(line.strip())
        if match:
            return _dump(
                {"related": [{"ref": int(match.group(1)), "reason": _LINK_REASON}], "contradicts": []}
            )
    return _dump({"related": [], "contradicts": []})


# ---------------------------------------------------------------- 4.5 Check-in Converter

_NUMBER_WORDS = {
    "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
    "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
}  # fmt: skip
_NUMBER = r"\d+(?:\.\d+)?|" + "|".join(_NUMBER_WORDS)
_SLEEP_HOURS_RE = re.compile(rf"\b({_NUMBER})\s*(?:hours?|hrs?|h)\b", re.I)
_SLEEP_WORD_RE = re.compile(r"\bsleep|\bslept", re.I)
_NOT_EXERCISED_RE = re.compile(
    r"\b(?:didn't exercise|did not exercise|no exercise|skipped (?:the )?gym|didn't work out|did not work out)\b", re.I
)
_EXERCISED_RE = re.compile(r"\b(?:exercised|worked out|went to the gym|went for a run)\b", re.I)
_MEALS = r"(breakfast|lunch|dinner)"
# "had ramen for lunch" (the food may not itself contain another had/ate)
_MEAL_FOR_RE = re.compile(
    rf"\b(?:had|ate)\s+((?:(?!\b(?:had|ate)\b)[^.!?\n,;])+?)\s+for\s+{_MEALS}\b", re.I
)
# "for lunch I had ramen" / "lunch: I ate ramen"
_MEAL_FIRST_RE = re.compile(rf"\b{_MEALS}\b[^.!?\n]*?\b(?:had|ate)\s+([^.!?\n,;]+)", re.I)
_FOCUS_GOOD_RE = re.compile(r"\bfocused well\b", re.I)
_FOCUS_BAD_RE = re.compile(r"\b(?:couldn't|could not|can't|cannot) focus\b", re.I)
_STRESS_LOW_RE = re.compile(r"\b(?:relaxed|no stress|not stressed|wasn't stressed)\b", re.I)
_STRESS_HIGH_RE = re.compile(r"\b(?:stressed|a lot of stress)\b", re.I)
_SENTENCE_SPLIT_RE = re.compile(r"(?:\.(?!\d)|[!?;\n])+")  # a "." inside 5.5 is not a sentence end


def _convert_checkin_english(text: str) -> dict:
    text = text.replace("’", "'")
    out: dict = {"sleep_hours": None, "exercised": None, "diet_note": None, "focus": None, "stress": None}

    # sleep_hours: a number followed by hours/h in a sentence that mentions sleep. Nothing else is inferred.
    for sentence in _SENTENCE_SPLIT_RE.split(text):
        if not _SLEEP_WORD_RE.search(sentence):
            continue
        m = _SLEEP_HOURS_RE.search(sentence)
        if m:
            raw = m.group(1).lower()
            hours = _NUMBER_WORDS[raw] if raw in _NUMBER_WORDS else round(float(raw))
            out["sleep_hours"] = hours if 0 <= hours <= 14 else None
            break

    if _NOT_EXERCISED_RE.search(text):
        out["exercised"] = False
    elif _EXERCISED_RE.search(text):
        out["exercised"] = True

    m = _MEAL_FOR_RE.search(text)
    if m:
        out["diet_note"] = f"{m.group(2).lower()}: {m.group(1).strip()}"
    else:
        m = _MEAL_FIRST_RE.search(text)
        if m:
            out["diet_note"] = f"{m.group(1).lower()}: {m.group(2).strip()}"

    if _FOCUS_BAD_RE.search(text):
        out["focus"] = 2
    elif _FOCUS_GOOD_RE.search(text):
        out["focus"] = 4
    if _STRESS_LOW_RE.search(text):
        out["stress"] = 2
    elif _STRESS_HIGH_RE.search(text):
        out["stress"] = 4
    return out


# Korean fallback: the original Korean rules, applied only to fields the English rules left empty.
_KOREAN_NUMBERS = {"한": 1, "두": 2, "세": 3, "네": 4, "다섯": 5, "여섯": 6, "일곱": 7, "여덟": 8, "아홉": 9, "열": 10}
_KO_SLEEP_RE = re.compile(r"(\d+(?:\.\d+)?|다섯|여섯|일곱|여덟|아홉|한|두|세|네|열)\s*시간")
_KO_NOT_EXERCISED_RE = re.compile(r"안\s*했|못\s*했|쉬었")
_KO_EXERCISED_RE = re.compile(r"했|갔")
_KO_MEAL_RE = re.compile(r"(아침|점심|저녁)(\S*)\s+([^.!?\n]*?)먹")


def _convert_checkin_korean(text: str, out: dict) -> None:
    if out["sleep_hours"] is None:
        m = _KO_SLEEP_RE.search(text)
        if m:
            raw = m.group(1)
            hours = _KOREAN_NUMBERS[raw] if raw in _KOREAN_NUMBERS else round(float(raw))
            out["sleep_hours"] = hours if 0 <= hours <= 14 else None
    if out["exercised"] is None and "운동" in text:
        if _KO_NOT_EXERCISED_RE.search(text):
            out["exercised"] = False
        elif _KO_EXERCISED_RE.search(text):
            out["exercised"] = True
    if out["diet_note"] is None:
        m = _KO_MEAL_RE.search(text)
        if m:
            # The word right before 먹, minus its object particle: "점심은 라면을 먹었고" -> "점심 라면".
            words = m.group(3).split()
            if words:
                word = re.sub(r"(을|를)$", "", words[-1])
                if word and word not in ("안", "못"):
                    out["diet_note"] = f"{m.group(1)} {word}"
    if out["focus"] is None:
        for sentence in [s for s in _SENTENCE_SPLIT_RE.split(text) if "집중" in s]:
            if "안" in sentence or "못" in sentence:
                out["focus"] = 2
            elif "잘" in sentence:
                out["focus"] = 4
            if out["focus"]:
                break
    if out["stress"] is None:
        for sentence in [s for s in _SENTENCE_SPLIT_RE.split(text) if "스트레스" in s]:
            if any(w in sentence for w in "많심높"):
                out["stress"] = 4
            elif any(w in sentence for w in "없적낮"):
                out["stress"] = 2
            if out["stress"]:
                break


def _convert_checkin(messages: list[Message]) -> str:
    text = _first_user(messages)
    out = _convert_checkin_english(text)
    _convert_checkin_korean(text, out)
    return _dump(out)


# ---------------------------------------------------------------- 4.6 Narrator / Recommender / Material Finder

_FACTS_RE = re.compile(r"<facts>\n(.*?)\n</facts>", re.S)
_NODES_RE = re.compile(r"<available_nodes>\n(.*?)\n</available_nodes>", re.S)
_CONDITION_RE = re.compile(r"^Condition: (\w+)", re.M)
_NODE_TITLE_RE = re.compile(r"^Node: (.*?) — ", re.M)
_GAP_RE = re.compile(r"^Gap: (.*)$", re.M)
_RESULT_INDEX_RE = re.compile(r"^\[(\d+)\] ", re.M)

_RECOMMEND_RATIONALE = "Prerequisites checked — you can take this on now."
_RECOMMEND_HINT = "Explain the why before the definition."
_FINDER_REASON = "Covers this gap directly."


def _times(n: int) -> str:
    return "1 time" if n == 1 else f"{n} times"


def _narrate(messages: list[Message]) -> str:
    match = _FACTS_RE.search(_system(messages))
    facts = json.loads(match.group(1)) if match else {}
    nodes = facts.get("nodes", {})
    sentences = [f"You've cleared {nodes.get('mastered', 0)} of {nodes.get('total', 0)} nodes."]
    for cluster in facts.get("misconception_clusters", []):
        sentences.append(
            f"The misconception “{cluster['label']}” showed up {_times(cluster['occurrences'])} "
            f"in {', '.join(cluster['skills'])}."
        )
    condition = facts.get("condition", {})
    if condition.get("avg_sleep_hours") is not None:
        days = condition["days"]
        span = "day" if days == 1 else f"{days} days"
        sentences.append(f"Average sleep over the last {span}: {condition['avg_sleep_hours']} h.")
    return _dump({"narrative": " ".join(sentences)[:400]})


def _recommend(messages: list[Message]) -> str:
    system = _system(messages)
    match = _NODES_RE.search(system)
    nodes = sorted(json.loads(match.group(1)) if match else [], key=lambda n: n["skill_id"])
    condition = _CONDITION_RE.search(system)
    if condition and condition.group(1) == "low":
        nodes.sort(key=lambda n: n["position"] != "leaf")  # stable: leaves first, ids within each group
    steps = [
        {"skill_id": n["skill_id"], "rationale": _RECOMMEND_RATIONALE, "focus_hint": _RECOMMEND_HINT}
        for n in nodes[:5]
    ]
    return _dump({"steps": steps})


def _find_material(messages: list[Message]) -> str:
    system = _system(messages)
    if "<results>" in system:  # step 2: pick
        indices = [int(i) for i in _RESULT_INDEX_RE.findall(system)]
        return _dump({"picks": [{"index": i, "reason": _FINDER_REASON} for i in indices[:3]]})
    title = _NODE_TITLE_RE.search(system)
    gap = _GAP_RE.search(system)
    title_text = title.group(1) if title else ""
    gap_text = gap.group(1).strip() if gap else ""
    return _dump({"queries": [f"{title_text} {gap_text[:30]}", f"{title_text} explained"]})


# ---------------------------------------------------------------- 契约第 5 节：前台

_NODES_BLOCK_RE = re.compile(r"<nodes>\n(.*?)\n</nodes>", re.S)
_OPEN_WORDS_RE = re.compile(r"\b(?:challenge|audit|try|open|continue|start)", re.I)
_CHECKIN_WORDS_RE = re.compile(
    r"\b(?:sleep|slept|exercis|worked out)|\b(?:tired|ate)\b|\bhad .* for (?:breakfast|lunch|dinner)\b|\blog my day\b|\bmy day\b",
    re.I,
)
_COURSE_WORDS_RE = re.compile(r"\b(?:learn|study|build|make|create|teach me)", re.I)
_PLAN_WORDS_RE = re.compile(r"\bquest|\bwhat should i\b|\brecommend", re.I)
_BRIEFING_WORDS_RE = re.compile(r"\bstatus\b|\breport\b|\bhow am i doing\b", re.I)
_MAP_WORDS_RE = re.compile(r"\bmap\b|\bworld\b", re.I)
_TOPIC_HEAD_RE = re.compile(
    r"^\s*(?:i want to learn|i'd like to learn|i want to study|teach me|build me a world (?:for|about)|make a world (?:for|about))(?:\s+|$)",
    re.I,
)
_TOPIC_TAIL_RE = re.compile(r"[\s.!?]+$")
_NO_TOPIC = {"this", "this file", "these"}  # with an upload these mean "use the file", not a topic

_FRONT_REPLIES = {
    "none": "Sure. What would you like to do today?",
    "checkin": "Got it, logging that.",
    "plan": "Let me pick today's quests.",
    "briefing": "Let me sum up where you are.",
    "open_map": "Opening your life tree.",
}
_ASK_TOPIC = "What topic should I build?"


def _front_desk(messages: list[Message]) -> str:
    message = _first_user(messages).strip().replace("’", "'")
    block = _NODES_BLOCK_RE.search(_system(messages))
    titles = [line[2:].strip() for line in (block.group(1).splitlines() if block else []) if line.startswith("- ")]
    # The longest matching title wins, so "Quadratic Equations" beats a shorter title inside it.
    lowered = message.casefold()
    matched = sorted(
        (t for t in titles if t and t != "(none)" and t.casefold() in lowered), key=len, reverse=True
    )

    def out(intent: str, reply: str, args: dict | None = None) -> str:
        return _dump({"intent": intent, "args": args or {}, "reply": reply})

    if matched and _OPEN_WORDS_RE.search(message):
        return out("open_skill", f"Taking you to “{matched[0]}”.", {"skill": matched[0]})
    if _CHECKIN_WORDS_RE.search(message):
        return out("checkin", _FRONT_REPLIES["checkin"])
    if _COURSE_WORDS_RE.search(message):
        topic = _TOPIC_HEAD_RE.sub("", _TOPIC_TAIL_RE.sub("", message)).strip()
        if not topic or topic.casefold() in _NO_TOPIC:
            return out("none", _ASK_TOPIC)
        return out("generate_course", f"I'll build a world for “{topic}”.", {"topic": topic})
    if _PLAN_WORDS_RE.search(message):
        return out("plan", _FRONT_REPLIES["plan"])
    if _BRIEFING_WORDS_RE.search(message):
        return out("briefing", _FRONT_REPLIES["briefing"])
    if _MAP_WORDS_RE.search(message):
        return out("open_map", _FRONT_REPLIES["open_map"])
    return out("none", _FRONT_REPLIES["none"])


_SCRIPTS = {
    "clarifier": _clarify,
    "syllabus_finder": _syllabus,
    "planner": _plan,
    "auditor": _audit,
    "challenger": _challenge,
    "recorder": _record,
    "linker": _link,
    "checkin_converter": _convert_checkin,
    "narrator": _narrate,
    "recommender": _recommend,
    "material_finder": _find_material,
    "front_desk": _front_desk,
}


class MockProvider:
    name = "mock"

    def complete(self, messages: list[Message]) -> str:
        start = time.perf_counter()
        agent = agent_of(messages)
        script = _SCRIPTS.get(agent) if agent else None
        if script is None:
            raise ValueError(f"MockProvider has no script for agent {agent!r}")
        result = script(messages)
        elapsed_ms = (time.perf_counter() - start) * 1000
        logger.info("mock complete() success agent=%s elapsed_ms=%.0f", agent or "-", elapsed_ms)
        return result
