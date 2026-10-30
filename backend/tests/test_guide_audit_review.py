"""The Guide reads audits (intent audit_review, no LLM beyond the front desk) and answers in the
language the user wrote in."""

import json

import pytest
from sqlmodel import Session

from app.agents.front_desk import FrontDesk
from app.config import settings
from app.i18n import current_language
from app.llm import decisions
from app.models import AuditStatus
from tests.helpers import ScriptedProvider, make_audit, make_course, make_skill
from tests.test_front_desk_decisions import deciding


def desk(intent="audit_review", reply="Let me look."):
    return json.dumps({"intent": intent, "args": {}, "reply": reply})


def use(monkeypatch, provider):
    monkeypatch.setattr("app.routers.chat.get_provider", lambda agent=None: provider)


def chat(client, message, language=None):
    headers = {"Accept-Language": language} if language else {}
    response = client.post("/api/chat", json={"message": message}, headers=headers)
    assert response.status_code == 200, response.text
    return response.json()["messages"]


def seed(client_engine, statuses):
    """Audits oldest first on one node; the failed ones carry gaps with evidence."""
    with Session(client_engine) as session:
        skill = make_skill(session, make_course(session), "q", "Quadratic Equations")
        audits = []
        for status in statuses:
            kwargs = {}
            if status == AuditStatus.failed:
                kwargs = {
                    "gaps_json": json.dumps(["g1", "g2", "g3", "g4"]),
                    "evidence_json": json.dumps([{"gap": "g1", "said": "s", "right": "r1"}, {"gap": "g2", "said": "s", "right": "r2"}]),
                }
            audits.append(make_audit(session, skill, status, **kwargs).id)
        return audits


def test_audit_review_lists_the_last_failed_audits_gaps(client, client_engine, monkeypatch):
    first, second, third = seed(client_engine, [AuditStatus.failed, AuditStatus.passed, AuditStatus.failed])
    provider = ScriptedProvider(front_desk=desk())
    use(monkeypatch, provider)

    reply = chat(client, "what did I get wrong last time")[1]

    lines = reply["content"].split("\n")
    assert lines[0] == "Your last failed audit was on “Quadratic Equations”. Where it fell short:"
    assert lines[1:4] == ["- g1 — r1", "- g2 — r2", "- g3"]
    assert lines[4] == "1 of your last 3 audits passed."
    assert len(lines) == 5  # at most three gaps
    assert reply["action"] == {"type": "navigate", "scene": "audit", "audit_id": third}
    assert len(provider.calls) == 1  # the front desk only


def test_audit_review_skips_active_audits_and_says_when_nothing_failed(client, client_engine, monkeypatch):
    seed(client_engine, [AuditStatus.passed, AuditStatus.active])
    use(monkeypatch, ScriptedProvider(front_desk=desk()))

    reply = chat(client, "how did my audits go")[1]

    assert reply["content"] == "No failed audit lately.\n1 of your last 1 audits passed."
    assert reply["action"] is None


def test_audit_review_without_audits_says_so(client, monkeypatch):
    use(monkeypatch, ScriptedProvider(front_desk=desk()))

    reply = chat(client, "我上次哪里错了")[1]

    assert reply["content"] == "你还没有完成过审计。去挑战一个节点，我才有东西可以给你看。"
    assert reply["action"] is None


def test_audit_review_in_chinese_and_korean(client, client_engine, monkeypatch):
    seed(client_engine, [AuditStatus.failed])
    use(monkeypatch, ScriptedProvider(front_desk=desk()))

    zh = chat(client, "我上次哪里错了", "zh")[1]["content"].split("\n")
    ko = chat(client, "지난번에 뭐 틀렸어", "ko")[1]["content"].split("\n")

    assert zh[0] == "你最近一次没通过的审计是「Quadratic Equations」。问题出在："
    assert zh[1] == "- g1 — r1"
    assert zh[-1] == "最近 1 次审计里通过了 0 次。"
    assert ko[-1] == "최근 감사 1번 중 0번 통과했어요."


def test_the_fast_path_routes_audit_review_without_the_llm(client, client_engine, monkeypatch):
    seed(client_engine, [AuditStatus.failed])
    provider = ScriptedProvider()
    use(monkeypatch, provider)
    monkeypatch.setattr(settings, "openai_api_key", "sk-test")
    monkeypatch.setattr(decisions, "decide", deciding("audit_review"))

    reply = chat(client, "what did I get wrong last time")[1]

    assert reply["content"].startswith("Your last failed audit was on")
    assert provider.calls_for("front_desk") == []


def test_front_desk_agent_knows_the_intent():
    result = FrontDesk(ScriptedProvider(front_desk=desk())).route("what went wrong", [])
    assert result.intent == "audit_review"


# ---------------------------------------------------------------- the reply's language


class LanguageSpy(ScriptedProvider):
    seen: list[str]

    def complete(self, messages):
        self.seen = [*getattr(self, "seen", []), current_language()]
        return super().complete(messages)


@pytest.mark.parametrize(
    "message, ui, expected",
    [
        ("我想知道今天该学什么", "en", "zh"),
        ("오늘 뭘 공부해야 해?", "en", "ko"),
        ("what should I study today", "zh", "en"),
        ("好", "en", "en"),  # one character: cannot tell, the UI language stays
        ("ok", "zh", "zh"),  # one word: cannot tell
    ],
)
def test_the_front_desk_answers_in_the_language_of_the_message(client, monkeypatch, message, ui, expected):
    provider = LanguageSpy(front_desk=desk("none", "Sure."))
    use(monkeypatch, provider)

    chat(client, message, ui)

    assert provider.seen[0] == expected


def test_a_fixed_reply_follows_the_message_language_too(client, monkeypatch):
    use(monkeypatch, ScriptedProvider())
    monkeypatch.setattr(settings, "openai_api_key", "sk-test")
    monkeypatch.setattr(decisions, "decide", deciding("open_map"))

    assert chat(client, "给我看看地图", "en")[1]["content"] == "这是你的人生树。"


def test_the_offline_guide_knows_the_question_too(client):
    for message in ("what did I get wrong last time?", "我上次哪里错了", "지난번에 뭐 틀렸어?"):
        body = client.post("/api/chat", json={"message": message}).json()
        replies = " ".join(m["content"] for m in body["messages"] if m["role"] != "user")
        assert any(word in replies for word in ("finished an audit", "完成过审计", "끝낸 감사")), body
