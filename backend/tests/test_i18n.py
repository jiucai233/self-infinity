"""The request's language (Accept-Language: en / zh / ko): fixed texts, LLM instruction, reflections."""

import pytest

from app import i18n
from app.llm.base import with_language
from app.models import NodeType, SkillNode
from app.services.audit_flow import opening_question
from app.services.tree import NodePosition


@pytest.fixture
def language():
    """Sets the request language for one test, the way LanguageMiddleware does."""
    tokens = []

    def use(code: str) -> None:
        tokens.append(i18n.set_language(code))

    yield use
    for token in reversed(tokens):
        i18n.reset_language(token)


@pytest.mark.parametrize(
    ("header", "expected"),
    [
        (None, "en"),
        ("", "en"),
        ("zh", "zh"),
        ("zh-CN,zh;q=0.9,en;q=0.8", "zh"),
        ("ko-KR", "ko"),
        ("fr-FR, ko;q=0.5", "ko"),
        ("ja", "en"),
    ],
)
def test_the_first_supported_tag_of_accept_language_wins(header, expected):
    assert i18n.parse_accept_language(header) == expected


def test_english_prompts_are_sent_unchanged(language):
    messages = [{"role": "system", "content": "[agent: auditor]\nRules."}, {"role": "user", "content": "hi"}]
    assert with_language(messages) == messages


def test_other_languages_add_one_instruction_to_the_system_prompt_and_keep_ids_english(language):
    language("ko")
    messages = [{"role": "system", "content": "[agent: auditor]\nRules."}, {"role": "user", "content": "hi"}]

    sent = with_language(messages)

    assert sent[0]["content"].startswith("[agent: auditor]\nRules.")  # Mock routing still works
    assert "Korean (한국어)" in sent[0]["content"]
    assert "slugs" in sent[0]["content"]
    assert sent[1] == messages[1]
    assert messages[0]["content"] == "[agent: auditor]\nRules."  # the caller's list is untouched


def test_the_real_provider_sends_the_instruction(language, monkeypatch):
    from tests.test_deepseek_provider import _content_response, _make_provider

    language("zh")
    provider, client = _make_provider(_content_response('{"ok": true}'))
    monkeypatch.setattr(type(provider), "model", property(lambda self: "m"), raising=False)
    provider.complete([{"role": "system", "content": "[agent: clarifier]"}, {"role": "user", "content": "x"}])

    system = client.last_kwargs["json"]["messages"][0]["content"]
    assert "Simplified Chinese (简体中文)" in system


def _node(title: str, node_type: NodeType = NodeType.concept) -> SkillNode:
    return SkillNode(id=1, course_id=1, slug="n", title=title, description="", node_type=node_type)


def test_opening_questions_follow_the_language_with_its_quotation_marks(language):
    assert opening_question(_node("Limits"), NodePosition.leaf, []) == (
        "Explain “Limits” from scratch to someone who has never heard of it."
    )
    language("zh")
    assert opening_question(_node("极限"), NodePosition.leaf, []) == "向一个从没听说过「极限」的人，从头讲清楚它。"
    assert "导数、积分" in opening_question(_node("微积分"), NodePosition.branch, ["导数", "积分"])
    language("ko")
    assert opening_question(_node("미적분"), NodePosition.root, []).startswith("“미적분”:")


def test_the_endpoints_answer_in_the_header_language(client):
    def labels(lang: str) -> list[str]:
        response = client.get("/api/chat/suggestions", headers={"Accept-Language": lang})
        return [s["label"] for s in response.json()["suggestions"]]

    assert labels("en")[-1] == "Tell me what you want to learn"
    assert labels("zh")[-1] == "告诉我你想学什么"
    assert labels("ko")[-1] == "배우고 싶은 걸 알려 주세요"
    # Nothing leaks into the next request.
    assert client.get("/api/chat/suggestions").json()["suggestions"][-1]["label"] == "Tell me what you want to learn"


def test_a_reflection_answered_in_one_language_counts_in_the_others(language):
    for index in range(7):
        variants = i18n.reflection_variants(index)
        assert len(set(variants)) == 3
        assert all(i18n.is_reflection_prompt(v) for v in variants)
    language("ko")
    assert i18n.reflection_prompt(1) == "지금 미루고 있는 게 뭔가요?"


def test_every_text_has_all_three_languages_with_the_same_placeholders():
    import string

    for key, texts in i18n._TEXTS.items():
        assert set(texts) == set(i18n.SUPPORTED), key
        fields = {tuple(sorted(f for _, f, _, _ in string.Formatter().parse(t) if f)) for t in texts.values()}
        assert len(fields) == 1, key
    for prompts in i18n._REFLECTION_PROMPTS.values():
        assert len(prompts) == 7
