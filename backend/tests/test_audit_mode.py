"""夜晚模式（深度审计）：会话创建时把 max_turns 翻倍并固定存在 AuditSession 上，
让审计能在真正复杂的话题上多追问几轮，而不是被 day 模式的默认上限强制收敛。"""

from unittest.mock import patch

from app.agents.auditor import Auditor
from app.config import settings
from app.llm.base import Message
from app.models import NodeType

DAY_CONCEPT_MAX_TURNS = settings.audit_max_turns
NIGHT_CONCEPT_MAX_TURNS = settings.audit_max_turns * 2


class StubbornProbeProvider:
    """无论轮次多少，永远返回一个格式合法的 probe——用来把审计一路推到强制裁决为止。"""

    name = "stubborn-probe"

    def complete(self, messages: list[Message]) -> str:
        return '{"action": "probe", "question": "还是不够具体，再说说？"}'


def _root_skill_id(client) -> int:
    skills = client.get("/api/skills").json()
    return next(s["id"] for s in skills if s["slug"] == "big-o")


def test_night_mode_doubles_max_turns_at_the_auditor_level():
    auditor = Auditor(StubbornProbeProvider())
    history: list[Message] = []

    for turn in range(NIGHT_CONCEPT_MAX_TURNS + 3):
        result = auditor.next_turn(
            skill_title="测试技能",
            skill_description="用于夜晚模式测试",
            history=history,
            node_type=NodeType.concept,
            max_turns=NIGHT_CONCEPT_MAX_TURNS,
        )
        user_turn_count = sum(1 for m in history if m["role"] == "user")
        if result.is_verdict:
            # 不应该在 day 模式的上限处就被强制收敛
            assert user_turn_count >= NIGHT_CONCEPT_MAX_TURNS
            return
        history.append({"role": "assistant", "content": result.question or ""})
        history.append({"role": "user", "content": "还是原来那个答案。"})

    raise AssertionError("夜晚模式未能在放宽后的上限内收敛")


def test_start_audit_night_mode_stores_doubled_max_turns_for_concept(client):
    skill_id = _root_skill_id(client)
    start = client.post(f"/api/skills/{skill_id}/audits", json={"mode": "night"})
    assert start.status_code == 200
    audit_id = start.json()["session"]["id"]

    from app.db import get_session
    from app.main import app

    session_dep = app.dependency_overrides[get_session]
    with next(session_dep()) as db:
        from app.models import AuditSession

        audit = db.get(AuditSession, audit_id)
        assert audit.max_turns == NIGHT_CONCEPT_MAX_TURNS


def test_start_audit_default_mode_matches_existing_day_behavior(client):
    skill_id = _root_skill_id(client)
    start = client.post(f"/api/skills/{skill_id}/audits")
    audit_id = start.json()["session"]["id"]

    from app.db import get_session
    from app.main import app

    session_dep = app.dependency_overrides[get_session]
    with next(session_dep()) as db:
        from app.models import AuditSession

        audit = db.get(AuditSession, audit_id)
        assert audit.max_turns == DAY_CONCEPT_MAX_TURNS


def test_start_audit_invalid_mode_rejected(client):
    skill_id = _root_skill_id(client)
    resp = client.post(f"/api/skills/{skill_id}/audits", json={"mode": "midnight"})
    assert resp.status_code == 422


def test_night_mode_audit_survives_more_than_four_rounds_before_forced_verdict(client):
    skill_id = _root_skill_id(client)
    start = client.post(f"/api/skills/{skill_id}/audits", json={"mode": "night"})
    audit_id = start.json()["session"]["id"]

    with patch("app.routers.audits.get_provider", return_value=StubbornProbeProvider()):
        results = []
        for _ in range(NIGHT_CONCEPT_MAX_TURNS + 2):
            resp = client.post(f"/api/audits/{audit_id}/turns", json={"content": "还是原来那个答案。"})
            body = resp.json()
            results.append(body)
            if body["type"] == "verdict":
                break

    verdict_index = next(i for i, r in enumerate(results) if r["type"] == "verdict")
    # user_turn_count at forced verdict time is verdict_index + 1 (this turn's user
    # message was already recorded before the auditor ran) and must reach the
    # night-mode ceiling, not the day-mode one.
    assert verdict_index + 1 >= NIGHT_CONCEPT_MAX_TURNS
    assert results[-1]["passed"] is False


def test_day_mode_audit_still_forces_verdict_at_four_rounds(client):
    skill_id = _root_skill_id(client)
    start = client.post(f"/api/skills/{skill_id}/audits", json={"mode": "day"})
    audit_id = start.json()["session"]["id"]

    with patch("app.routers.audits.get_provider", return_value=StubbornProbeProvider()):
        results = []
        for _ in range(DAY_CONCEPT_MAX_TURNS + 2):
            resp = client.post(f"/api/audits/{audit_id}/turns", json={"content": "还是原来那个答案。"})
            body = resp.json()
            results.append(body)
            if body["type"] == "verdict":
                break

    verdict_index = next(i for i, r in enumerate(results) if r["type"] == "verdict")
    assert verdict_index + 1 == DAY_CONCEPT_MAX_TURNS
    assert results[-1]["passed"] is False
