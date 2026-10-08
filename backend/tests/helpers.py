"""Shared test fixtures-as-functions: factories, scripted providers, answer builders.

The Mock demo script (docs/api-contract.md section 4) is deterministic, so most API tests
steer the Auditor and the Challenger just by how long the answers are. The provider stubs
here are for the cases the script cannot produce (a failing provider, malformed output).
"""

import json
from datetime import datetime
from zoneinfo import ZoneInfo

from sqlmodel import Session

from app.llm.base import Message, agent_of
from app.llm.mock import MockProvider
from app.models import (
    AuditSession,
    AuditStatus,
    Course,
    EdgeKind,
    NodeType,
    Principle,
    SkillEdge,
    SkillNode,
    SkillStatus,
)

# ---------------------------------------------------------------- 回答长度（契约 4.3）
#
# Mock Auditor：第一个回答一律追问；之后的回答按"所有回答的总字数 n"裁决——
# n < 80 不通过，n ≥ 80 通过；Challenger 在 n < 160 时推翻（每场一次）。


def text(n: int) -> str:
    """Exactly n characters, with no whitespace (request bodies are stripped, which would
    otherwise change the length the Mock script counts)."""
    return ("reasonfirst" * (n // 11 + 1))[:n]


FIRST = text(10)  # the first answer only ever gets a probe back
SHORT = text(20)  # first + second = 30  -> fail
MEDIUM = text(100)  # first + second = 110 -> pass, but the Challenger overturns (n < 160)
LONG = text(200)  # first + second = 210 -> pass at once


def answer_turns(client, audit_id: int, *answers: str) -> list[dict]:
    """Post each answer in order and return the JSON results."""
    results = []
    for answer in answers:
        response = client.post(f"/api/audits/{audit_id}/turns", json={"content": answer})
        assert response.status_code == 200, response.text
        results.append(response.json())
    return results


def start(client, skill_id: int, mode: str = "day") -> int:
    response = client.post(f"/api/skills/{skill_id}/audits", json={"mode": mode})
    assert response.status_code == 200, response.text
    return response.json()["session"]["id"]


def pass_node(client, skill_id: int) -> dict:
    """Audit a node to a pass with a long answer; returns the verdict."""
    audit_id = start(client, skill_id)
    _probe, verdict = answer_turns(client, audit_id, FIRST, LONG)
    assert verdict["type"] == "verdict" and verdict["passed"] is True, verdict
    return verdict


def fail_node(client, skill_id: int) -> int:
    """Audit a node to a fail with short answers; returns the audit id."""
    audit_id = start(client, skill_id)
    _probe, verdict = answer_turns(client, audit_id, FIRST, SHORT)
    assert verdict["type"] == "verdict" and verdict["passed"] is False, verdict
    return audit_id


# ---------------------------------------------------------------- 课程

def generate(client, topic: str = "Math", **settings) -> dict:
    response = client.post("/api/skills/generate", json={"topic": topic, **settings})
    assert response.status_code == 200, response.text
    return response.json()


def ids_by_slug(generated: dict) -> dict[str, int]:
    return {n["slug"]: n["id"] for n in generated["nodes"]}


# The Mock math course in learning order (services/tree.py): each chapter opens its first node not
# yet mastered, so passing them in this order always takes an open node.
MATH_ORDER = [
    "discriminant",
    "root-coefficient",
    "quadratic-equation",
    "linear-function",
    "quadratic-function",  # requires linear-function and quadratic-equation
    "functions",
    "sequence-limit",
    "sequences",
    "algebra",
    "derivative",  # requires sequence-limit
    "calculus",
    "high-school-math",
]


# ---------------------------------------------------------------- 直接造数据库行

def make_course(session: Session, topic: str = "Test course") -> Course:
    course = Course(topic=topic)
    session.add(course)
    session.commit()
    session.refresh(course)
    return course


def make_skill(
    session: Session,
    course: Course,
    slug: str,
    title: str | None = None,
    *,
    status: SkillStatus = SkillStatus.available,
    node_type: NodeType = NodeType.concept,
    description: str = "Description",
) -> SkillNode:
    skill = SkillNode(
        course_id=course.id,
        slug=slug,
        title=title or slug,
        description=description,
        status=status,
        node_type=node_type,
    )
    session.add(skill)
    session.commit()
    session.refresh(skill)
    return skill


def link(session: Session, from_node: SkillNode, to_node: SkillNode, kind: EdgeKind, primary: bool | None = None, reason=None):
    if kind == EdgeKind.contains and primary is None:
        primary = True
    session.add(
        SkillEdge(from_id=from_node.id, to_id=to_node.id, kind=kind, is_primary=primary, reason=reason)
    )
    session.commit()


def make_audit(session: Session, skill: SkillNode, status: AuditStatus = AuditStatus.failed, **kwargs) -> AuditSession:
    audit = AuditSession(skill_id=skill.id, status=status, **kwargs)
    session.add(audit)
    session.commit()
    session.refresh(audit)
    return audit


def make_principle(
    session: Session,
    skill: SkillNode,
    title: str = "Lesson",
    misconception: str | None = "A wrong idea",
    body: str = "When …, I ….",
) -> Principle:
    audit = make_audit(session, skill)
    principle = Principle(title=title, body=body, misconception=misconception, source_session_id=audit.id)
    session.add(principle)
    session.commit()
    session.refresh(principle)
    return principle


def set_status(session: Session, skill_id: int, status: SkillStatus) -> None:
    skill = session.get(SkillNode, skill_id)
    skill.status = status
    session.add(skill)
    session.commit()


# ---------------------------------------------------------------- Provider 替身


class BrokenProvider:
    """Every call fails, like a provider outage."""

    name = "broken"

    def complete(self, messages: list[Message]) -> str:
        raise RuntimeError("provider is down")


class ScriptedProvider:
    """Answers per sub-agent from a script, recording every call.

    `script` maps an agent name ("planner", "auditor", ...) to either a string, a list of
    strings (consumed in order, the last one repeats) or a callable(messages) -> str.
    Agents without an entry fall back to the Mock's contract script.
    """

    name = "scripted"

    def __init__(self, **script):
        self._script = script
        self._fallback = MockProvider()
        self.calls: list[tuple[str | None, list[Message]]] = []

    def calls_for(self, agent: str) -> list[list[Message]]:
        return [messages for name, messages in self.calls if name == agent]

    def system_prompts(self, agent: str) -> list[str]:
        return [next(m["content"] for m in messages if m["role"] == "system") for messages in self.calls_for(agent)]

    def complete(self, messages: list[Message]) -> str:
        agent = agent_of(messages)
        self.calls.append((agent, messages))
        entry = self._script.get(agent)
        if entry is None:
            return self._fallback.complete(messages)
        if callable(entry):
            return entry(messages)
        if isinstance(entry, list):
            # JSON 重试时 complete 会被再调一次，那一次也要消耗脚本里的下一项。
            index = min(len(self.calls_for(agent)) - 1, len(entry) - 1)
            return entry[index]
        return entry


class CountingProvider(MockProvider):
    """The Mock, plus a count of calls per sub-agent."""

    def __init__(self):
        self.counts: dict[str, int] = {}

    def complete(self, messages: list[Message]) -> str:
        agent = agent_of(messages) or "-"
        self.counts[agent] = self.counts.get(agent, 0) + 1
        return super().complete(messages)


def planner_json(nodes: list[tuple], requires: list[tuple] = ()) -> str:
    """Planner output from compact tuples: (slug, parents) or (slug, parents, title)."""
    items = []
    for node in nodes:
        slug, parents, *rest = node
        title = rest[0] if rest else slug
        items.append(
            {"slug": slug, "title": title, "description": f"{title} description", "parents": list(parents), "node_type": "concept"}
        )
    return json.dumps(
        {"nodes": items, "requires": [{"from": a, "to": b, "reason": "Reason"} for a, b in requires]},
        ensure_ascii=False,
    )


def verdict_json(passed: bool, score: int = 80, gaps=(), comment: str = "Verdict") -> str:
    return json.dumps(
        {"action": "verdict", "pass": passed, "score": score, "gaps": list(gaps), "comment": comment},
        ensure_ascii=False,
    )


def probe_json(question: str = "Could you say more?") -> str:
    return json.dumps({"action": "probe", "question": question}, ensure_ascii=False)


# ---------------------------------------------------------------- 时钟

def freeze_clock(monkeypatch, when: str = "2026-10-05 12:00", tz: str = "Asia/Seoul"):
    """Freeze `app.utils.local_now` (and so local_today) at a KST wall-clock time, "YYYY-MM-DD HH:MM".

    Returns a function that moves the clock to another time.
    """
    now = {"value": datetime.fromisoformat(when).replace(tzinfo=ZoneInfo(tz))}
    monkeypatch.setattr("app.utils.local_now", lambda: now["value"])

    def move(new_when: str) -> None:
        now["value"] = datetime.fromisoformat(new_when).replace(tzinfo=ZoneInfo(tz))

    return move
