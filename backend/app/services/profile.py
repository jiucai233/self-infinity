"""Profile Builder (plan 7.4, code, no LLM): the facts about the user.

The Narrator, the Recommender and the briefing page read these facts. Everything here is
database queries and plain arithmetic, so the briefing page can show fresh facts instantly.

Misconception clusters group `Principle.misconception` texts by keyword overlap
(app/services/text_overlap.py, single linkage). A cluster spanning 2 or more different
skills is `cross_skill`. The threshold is to be calibrated (plan 8.5).
"""

from dataclasses import dataclass, field
from datetime import datetime

from sqlmodel import Session, func, select

from app.services.courses import live_nodes
from app.models import AuditSession, AuditStatus, Principle, RewardEvent, SkillNode, SkillStatus, as_utc
from app.schemas import (
    AuditCounts,
    ConditionOut,
    MisconceptionClusterOut,
    NodeCounts,
    ProfileFacts,
    XpOut,
)
from app.services.condition import current_condition
from app.services.incentive import NODES_PER_LEVEL, global_level
from app.services.text_overlap import relevance_score

CLUSTER_THRESHOLD = 6


@dataclass
class MisconceptionCluster:
    label: str
    occurrences: int
    skills: list[str]  # distinct, in order of first appearance
    last_seen: datetime
    principle_ids: list[int] = field(default_factory=list)

    @property
    def cross_skill(self) -> bool:
        return len(self.skills) >= 2


def _load_rows(session: Session) -> list[tuple[Principle, str]]:
    """Principles with a misconception, oldest first, with the title of their audit's node.

    Outer joins: a principle whose audit chain is broken still counts.
    """
    rows = session.exec(
        select(Principle, SkillNode.title)
        .outerjoin(AuditSession, AuditSession.id == Principle.source_session_id)
        .outerjoin(SkillNode, SkillNode.id == AuditSession.skill_id)
        .where(Principle.misconception.is_not(None))
        .order_by(Principle.created_at, Principle.id)
    ).all()
    return [(p, title or "?") for p, title in rows if p.misconception]


def cluster_misconceptions(session: Session) -> list[MisconceptionCluster]:
    """Single-linkage clusters; cross-skill first, then more occurrences, then most recent."""
    rows = _load_rows(session)
    n = len(rows)
    parent = list(range(n))

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for i in range(n):
        for j in range(i + 1, n):
            if relevance_score(rows[i][0].misconception, rows[j][0].misconception) >= CLUSTER_THRESHOLD:
                ri, rj = find(i), find(j)
                if ri != rj:
                    parent[max(ri, rj)] = min(ri, rj)  # the root is the earliest record

    grouped: dict[int, list[int]] = {}
    for i in range(n):
        grouped.setdefault(find(i), []).append(i)

    clusters = []
    for root, members in grouped.items():
        principles = [rows[i][0] for i in members]
        clusters.append(
            MisconceptionCluster(
                label=rows[root][0].misconception,
                occurrences=len(members),
                skills=list(dict.fromkeys(rows[i][1] for i in members)),
                last_seen=max(as_utc(p.created_at) for p in principles),
                principle_ids=[p.id for p in principles],
            )
        )
    clusters.sort(key=lambda c: (c.cross_skill, c.occurrences, c.last_seen), reverse=True)
    return clusters


def _round(value: float | None) -> float | None:
    return None if value is None else round(value, 1)


def build_profile(session: Session) -> ProfileFacts:
    skills = session.exec(live_nodes()).all()
    audits = session.exec(select(AuditSession)).all()
    condition = current_condition(session)

    def count_nodes(status: SkillStatus) -> int:
        return sum(1 for s in skills if s.status == status)

    return ProfileFacts(
        nodes=NodeCounts(
            total=len(skills),
            mastered=count_nodes(SkillStatus.mastered),
            available=count_nodes(SkillStatus.available),
            locked=count_nodes(SkillStatus.locked),
        ),
        audits=AuditCounts(
            total=len(audits),
            passed=sum(1 for a in audits if a.status == AuditStatus.passed),
            failed=sum(1 for a in audits if a.status == AuditStatus.failed),
        ),
        misconception_clusters=[
            MisconceptionClusterOut(
                label=c.label,
                occurrences=c.occurrences,
                skills=c.skills,
                cross_skill=c.cross_skill,
                principle_ids=c.principle_ids,
            )
            for c in cluster_misconceptions(session)
        ],
        condition=ConditionOut(
            days=condition.days,
            avg_sleep_hours=_round(condition.avg_sleep_hours),
            avg_stress=_round(condition.avg_stress),
            flag=condition.flag,
        ),
        xp=XpOut(
            total=session.exec(select(func.coalesce(func.sum(RewardEvent.amount), 0))).one(),
            level=global_level(session),
            level_progress=(count_nodes(SkillStatus.mastered) % NODES_PER_LEVEL) / NODES_PER_LEVEL,
        ),
    )
