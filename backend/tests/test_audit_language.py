"""An audit is held in the user's language, whatever the interface is set to: the one they
answer in, and before any answer the node's own when that is not English."""

import pytest
from sqlmodel import Session

from app.agents.auditor import POINTS_VERDICT, SYSTEM_PROMPT
from app.i18n import current_language, language_of, use_language
from app.models import AuditSession, SkillNode, SkillStatus
from app.services import audit_flow
from tests.helpers import ScriptedProvider, generate, ids_by_slug, probe_json, set_status


@pytest.mark.parametrize(
    "text, language",
    [
        ("自注意力就是计算QKV三个矩阵，之后计算 key 对于 query 的相关性", "zh"),
        ("QKV 三个矩阵做 softmax，然后 scaled dot-product attention 的输出", "zh"),  # terms in English
        ("这个我不知道", "zh"),
        ("자기 주의는 Q, K, V 행렬로 관련성을 계산합니다", "ko"),
        ("It scores every pair and normalises the scores with a softmax.", "en"),
        ("Transformer 基础", "zh"),  # a character weighs as much as a word
        ("就是 discriminant b^2 - 4ac 的 sign 决定 roots 的个数", "zh"),
        ("The node 基础 covers attention and the feed forward layers", None),  # a mix: no call
        ("ok", None),  # one word
        ("I don't know", "en"),
        ("これは自己注意の説明です", None),  # Japanese is not one of ours
        ("42", None),
        ("", None),
    ],
)
def test_the_language_of_a_text_is_read_from_its_letters(text, language):
    assert language_of(text) == language


def test_use_language_holds_for_the_block_only():
    assert current_language() == "en"
    with use_language("zh"):
        assert current_language() == "zh"
        with use_language(None):  # nothing to say: it stays
            assert current_language() == "zh"
    assert current_language() == "en"


@pytest.fixture(name="node")
def node_fixture(client, client_engine):
    """A leaf of the math course, open, written in Chinese."""
    ids = ids_by_slug(generate(client, "math"))
    with Session(client_engine) as session:
        skill = session.get(SkillNode, ids["discriminant"])
        skill.title = "判别式"
        skill.description = "一元二次方程的判别式：它怎样决定根的个数"
        session.add(skill)
        session.commit()
        set_status(session, skill.id, SkillStatus.available)
    return ids["discriminant"]


def test_a_chinese_node_is_asked_in_chinese_under_an_english_interface(client, node):
    body = client.post(f"/api/skills/{node}/audits").json()

    assert body["opening_question"] == "我没学过「判别式」，你从头给我讲讲吧。"


def test_an_english_node_keeps_the_interface_language(client, client_engine):
    ids = ids_by_slug(generate(client, "math"))
    with Session(client_engine) as session:
        set_status(session, ids["discriminant"], SkillStatus.available)

    english = client.post(f"/api/skills/{ids['discriminant']}/audits").json()
    assert english["opening_question"] == "I have never learned “Discriminant”. Teach it to me from the start."
    chinese = client.post(
        f"/api/skills/{ids['discriminant']}/audits", json={"restart": True}, headers={"Accept-Language": "zh"}
    ).json()
    assert chinese["opening_question"] == "我没学过「Discriminant」，你从头给我讲讲吧。"


def test_she_answers_in_the_language_they_answer_in(client, client_engine, monkeypatch, node):
    spoken: list[str] = []

    def auditor(_messages) -> str:
        spoken.append(current_language())
        return probe_json("下一个问题")

    provider = ScriptedProvider(auditor=auditor)
    monkeypatch.setattr("app.routers.audits.get_provider", lambda agent=None: provider)
    audit_id = client.post(f"/api/skills/{node}/audits").json()["session"]["id"]

    def answer(text: str, **headers):
        assert client.post(f"/api/audits/{audit_id}/turns", json={"content": text}, headers=headers).status_code == 200

    answer("判别式大于零时有两个不同的实根")
    # One answer that leans on English terms does not turn the audit English.
    answer("就是 discriminant b^2 - 4ac 的 sign 决定 roots 的个数")
    assert spoken == ["zh", "zh"]
    # The interface language does not decide it either.
    answer("等于零时两个根重合", **{"Accept-Language": "ko"})
    assert spoken[-1] == "zh"


def test_english_answers_to_a_chinese_node_are_answered_in_english(client, client_engine, node):
    audit_id = client.post(f"/api/skills/{node}/audits").json()["session"]["id"]
    with Session(client_engine) as session:
        audit = session.get(AuditSession, audit_id)
        skill = session.get(SkillNode, node)
        assert audit_flow.audit_language(session, skill) == "zh"
        assert audit_flow.audit_language(session, skill, audit, "It tells how many real roots there are.") == "en"
        # Nothing to read the language from: the node's.
        assert audit_flow.audit_language(session, skill, audit, "42") == "zh"


def test_the_auditor_is_told_how_to_treat_a_question_about_its_question_and_a_point_of_several_things():
    # A question back is not an answer; a point is judged on what came up of it.
    assert "asks what your question means" in SYSTEM_PROMPT
    assert "It does not count as a second question." in SYSTEM_PROMPT
    assert "a part that never came up is not held against" in POINTS_VERDICT
    assert "Work out the answer yourself first" in SYSTEM_PROMPT
