"""The language of the current request, and the fixed texts the backend writes itself.

The app sends `Accept-Language: en | zh | ko` (its UI language) with every request;
`LanguageMiddleware` (app/main.py) puts it in a context variable for the whole request,
background tasks included. Two things follow it:

- the texts below (chat replies, suggestions, audit opening questions): `t(key, ...)`;
- every LLM call: the real providers append `language_instruction()` to the system prompt,
  so agents write learner-facing text in that language. The prompts themselves stay in
  English (one version to tune and test); ids, slugs, enum values and search queries stay
  English too.

Anything else — no header, another language — is English.
"""

import contextvars

SUPPORTED = ("en", "zh", "ko")

_language: contextvars.ContextVar[str] = contextvars.ContextVar("language", default="en")


def parse_accept_language(header: str | None) -> str:
    """The first supported primary tag of an Accept-Language header (`zh-CN` → `zh`), else `en`."""
    for part in (header or "").split(","):
        tag = part.split(";")[0].strip().lower().split("-")[0]
        if tag in SUPPORTED:
            return tag
    return "en"


def current_language() -> str:
    return _language.get()


def set_language(language: str) -> contextvars.Token:
    return _language.set(language if language in SUPPORTED else "en")


def reset_language(token: contextvars.Token) -> None:
    _language.reset(token)


_LANGUAGE_NAMES = {"zh": "Simplified Chinese (简体中文)", "ko": "Korean (한국어)"}


def language_instruction() -> str | None:
    """What the system prompt gains for a non-English request; None for English."""
    name = _LANGUAGE_NAMES.get(current_language())
    if name is None:
        return None
    return (
        f"Language: write every piece of text meant for the learner — questions, comments, "
        f"replies, titles, descriptions, reasons, rationales, hints, notes — in {name}, even "
        f"where the instructions above say English. Keep JSON keys, enum values, ids, slugs "
        f"and search queries exactly as the instructions above specify."
    )


def quote(title: str) -> str:
    """A title in the quotation marks of the language: “X”, or 「X」 in Chinese."""
    return f"「{title}」" if current_language() == "zh" else f"“{title}”"


def join_list(items: list[str]) -> str:
    return ("、" if current_language() == "zh" else ", ").join(items)


# key -> {language: template}. Templates use str.format; `{title}` and the like get quoted
# by the caller with quote(), so each language keeps its own quotation marks.
_TEXTS: dict[str, dict[str, str]] = {
    # chat replies (docs/english-strings.md section 4)
    "build_world": {
        "en": "I'll build a world for {topic}.",
        "zh": "我来为{topic}搭建一个世界。",
        "ko": "{topic} 세계를 만들어 볼게요.",
    },
    "world_ready": {
        "en": "Your world {title} is ready — {count} nodes.",
        "zh": "你的世界{title}准备好了——共 {count} 个节点。",
        "ko": "{title} 세계가 준비됐어요. 노드 {count}개.",
    },
    "world_merged": {
        "en": "You already have {title}, so I added to it instead: {added} new nodes.",
        "zh": "你已经有{title}这门课了，所以没有新建，而是补进了原来的树：新增 {added} 个节点。",
        "ko": "{title} 강좌가 이미 있어서 새로 만들지 않고 거기에 더했어요. 새 노드 {added}개.",
    },
    "world_failed": {
        "en": "I couldn't build that world. Please try again in a moment.",
        "zh": "这个世界没能建好，请稍后再试。",
        "ko": "그 세계를 만들지 못했어요. 잠시 뒤에 다시 시도해 주세요.",
    },
    "which_node": {
        "en": "Which node do you mean? Tell me its name.",
        "zh": "你说的是哪个节点？告诉我它的名字。",
        "ko": "어떤 노드 말인가요? 이름을 알려 주세요.",
    },
    "checkin_nothing": {
        "en": "I couldn't find anything to log. Tell me about sleep, exercise or meals.",
        "zh": "没找到可以记录的内容。说说你的睡眠、运动或饮食吧。",
        "ko": "기록할 내용을 찾지 못했어요. 수면, 운동, 식사에 대해 말해 주세요.",
    },
    "opening_node": {"en": "Opening {title}.", "zh": "打开{title}。", "ko": "{title}을 열게요."},
    "opening_map": {"en": "Here is your life tree.", "zh": "这是你的人生树。", "ko": "인생 나무를 보여 줄게요."},
    "logging_day": {"en": "Logging your day.", "zh": "我来记下你的今天。", "ko": "오늘 하루를 기록할게요."},
    "picking_quests": {"en": "Let me pick today's quests.", "zh": "我来挑今天的任务。", "ko": "오늘의 퀘스트를 골라 볼게요."},
    "status_coming": {"en": "Here is where you stand.", "zh": "这是你现在的状态。", "ko": "지금 상태를 정리해 볼게요."},
    "checkin_logged": {"en": "Logged: {parts}", "zh": "已记录：{parts}", "ko": "기록했어요: {parts}"},
    "checkin_sleep": {"en": "sleep {hours} h", "zh": "睡眠 {hours} 小时", "ko": "수면 {hours}시간"},
    "checkin_exercise_yes": {"en": "exercise yes", "zh": "运动 有", "ko": "운동 함"},
    "checkin_exercise_no": {"en": "exercise no", "zh": "运动 无", "ko": "운동 안 함"},
    "checkin_meals": {"en": "meals {note}", "zh": "饮食 {note}", "ko": "식사 {note}"},
    "checkin_focus": {"en": "focus {value}/5", "zh": "专注 {value}/5", "ko": "집중 {value}/5"},
    "checkin_stress": {"en": "stress {value}/5", "zh": "压力 {value}/5", "ko": "스트레스 {value}/5"},
    "no_node_ready": {
        "en": "No node is ready yet. Make a world first.",
        "zh": "还没有可挑战的节点。先建一个世界吧。",
        "ko": "아직 도전할 노드가 없어요. 먼저 세계를 만들어 보세요.",
    },
    "plan_failed": {
        "en": "I couldn't pick today's quests. Please try again.",
        "zh": "没能选出今天的任务，请再试一次。",
        "ko": "오늘의 퀘스트를 고르지 못했어요. 다시 시도해 주세요.",
    },
    "todays_quests": {"en": "Today's quests: {titles}.", "zh": "今天的任务：{titles}。", "ko": "오늘의 퀘스트: {titles}."},
    "briefing_failed": {
        "en": "I couldn't put your status together. Please try again.",
        "zh": "没能整理出你的状态，请再试一次。",
        "ko": "지금 상태를 정리하지 못했어요. 다시 시도해 주세요.",
    },
    # suggestions (section 3)
    "suggest_checkin_label": {"en": "How was your day?", "zh": "今天过得怎么样？", "ko": "오늘 하루 어땠어요?"},
    "suggest_checkin_message": {"en": "Let me log my day", "zh": "我来记录一下今天", "ko": "오늘 하루를 기록할게요"},
    "suggest_continue": {"en": "Continue {title}", "zh": "继续{title}", "ko": "{title} 이어서 하기"},
    "suggest_start": {"en": "Start with {title}", "zh": "从{title}开始", "ko": "{title}부터 시작하기"},
    "suggest_learn": {"en": "Tell me what you want to learn", "zh": "告诉我你想学什么", "ko": "배우고 싶은 걸 알려 주세요"},
    # audit opening questions, by tree position (section 5)
    "opening_leaf": {
        "en": "Explain {title} from scratch to someone who has never heard of it.",
        "zh": "向一个从没听说过{title}的人，从头讲清楚它。",
        "ko": "{title}에 대해 처음 듣는 사람에게 처음부터 설명해 보세요.",
    },
    "opening_branch": {
        "en": "{title} covers {children}. Why do these belong together, and when do you use which?",
        "zh": "{title}包括{children}。它们为什么归在一起？什么时候用哪个？",
        "ko": "{title} 아래에는 {children} 항목이 있어요. 왜 한데 묶일까요? 언제 어떤 걸 쓰나요?",
    },
    "opening_root": {
        "en": "Which problems call for {title}, and which don't? How do you decide?",
        "zh": "哪些问题需要用到{title}，哪些不需要？你怎么判断？",
        "ko": "{title}: 어떤 문제에 필요하고, 어떤 문제엔 필요 없을까요? 어떻게 판단하나요?",
    },
    "opening_test_out": {
        "en": "So you already know {title}. Prove it, one part at a time. Start with {part}: how does it work?",
        "zh": "你说{title}已经会了，那我们一块一块来验证。先从{part}开始：它是怎么工作的？",
        "ko": "{title}은 이미 안다고 했죠. 한 부분씩 확인해 볼게요. {part}부터: 어떻게 작동하나요?",
    },
    "opening_test_out_open": {
        "en": "So you already know {title}. Prove it: what are its main parts, and how does the most important one work?",
        "zh": "你说{title}已经会了，那来验证一下：它主要由哪几部分组成？最重要的那部分是怎么工作的？",
        "ko": "{title}은 이미 안다고 했죠. 확인해 볼게요: 주요 부분은 무엇이고, 가장 중요한 부분은 어떻게 작동하나요?",
    },
    "opening_task": {
        "en": "How exactly will you do {title}?",
        "zh": "你具体打算怎么完成{title}？",
        "ko": "{title}: 구체적으로 어떻게 해낼 건가요?",
    },
}


def t(key: str, **values: object) -> str:
    """The text `key` in the request's language, filled with `values`."""
    texts = _TEXTS[key]
    return texts.get(current_language(), texts["en"]).format(**values)


# The seven reflection prompts, one per KST time window (contract section 6), by language. A
# journal entry stores the prompt it answered in the language it was asked in; a window counts as
# answered whichever language that was (app/services/journal.py).
_REFLECTION_PROMPTS: dict[str, tuple[str, ...]] = {
    "en": (
        "Who are you becoming this week? One sentence.",
        "What are you putting off right now?",
        "Looking at the last two hours, what were you really after?",
        "Is today pulling you toward your vision or your anti-vision?",
        "What matters most that you've been ignoring?",
        "Today, were you guarding an image of yourself or going after what you want?",
        "When did you feel most alive today, and when least?",
    ),
    "zh": (
        "这周你正在成为什么样的人？一句话。",
        "你现在在拖延什么？",
        "回看过去两个小时，你真正在追求什么？",
        "今天是在把你拉向你想要的样子，还是你不想要的样子？",
        "有什么最重要的事，你一直在忽略？",
        "今天，你是在维护自己的形象，还是在追求你想要的东西？",
        "今天什么时候你最有活力，什么时候最没有？",
    ),
    "ko": (
        "이번 주 당신은 어떤 사람이 되어 가고 있나요? 한 문장으로.",
        "지금 미루고 있는 게 뭔가요?",
        "지난 두 시간을 돌아보면, 정말로 원했던 건 뭐였나요?",
        "오늘은 당신을 바라는 모습 쪽으로 이끄나요, 피하고 싶은 모습 쪽으로 이끄나요?",
        "가장 중요한데도 계속 외면해 온 건 뭔가요?",
        "오늘 당신은 자기 이미지를 지키고 있었나요, 원하는 걸 좇고 있었나요?",
        "오늘 언제 가장 살아 있다고 느꼈고, 언제 가장 그렇지 않았나요?",
    ),
}

ENGLISH_REFLECTION_PROMPTS = _REFLECTION_PROMPTS["en"]


def reflection_prompt(index: int) -> str:
    """Prompt `index` (0-6, in window order) in the request's language."""
    return _REFLECTION_PROMPTS.get(current_language(), ENGLISH_REFLECTION_PROMPTS)[index]


def reflection_variants(index: int) -> list[str]:
    """Prompt `index` in every language."""
    return [prompts[index] for prompts in _REFLECTION_PROMPTS.values()]


def is_reflection_prompt(text: str) -> bool:
    return any(text in prompts for prompts in _REFLECTION_PROMPTS.values())
