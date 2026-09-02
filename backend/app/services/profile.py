"""学习者画像：把散落的记录聚合成"关于这个用户的事实"。

系统里关于用户的信息一直是散的——技能节点在一张表、原则在另一张、体力和专注各自
一张。单看每一条都说明不了什么，Narrator 需要的是把它们合成一个整体状态。

这一层**完全不调用 LLM**：全是 DB 查询和纯计算，所以首屏可以秒开、可以随便刷新。
叙述（把这些事实讲成一段话）是 app/agents/narrator.py 的事，那才需要模型。

最有价值的计算是 misconception 聚类。库里存的是一条条孤立的
`Principle.misconception`（每次审计失败诊断出一条），但用户真正需要看见的不是
"你犯过 12 次错"，而是"你反复栽在同 3 个心智模型上，其中一个横跨了统计和投资两个
完全不相关的领域"。后者要靠把语义相同的记录归并成簇才能得到。
"""

from dataclasses import dataclass, field
from datetime import datetime

from sqlmodel import Session, select

from app.agents.retrieval import relevance_score
from app.models import (
    AuditSession,
    AuditStatus,
    FocusSession,
    Principle,
    SkillNode,
    SkillStatus,
    VitalityState,
    as_utc,
)

# 判定两条 misconception 是否指同一个心智模型的阈值。和
# retrieval._RECURRING_MISCONCEPTION_THRESHOLD 取同一个值不是巧合——那边判断
# "这次是不是又栽在同一处"，这边判断"历史上哪些属于同一处"，是同一个问题的单条版
# 和全库版，阈值不一致会让两处结论互相矛盾（弹窗说是复发，画像里却分成两簇）。
CLUSTER_THRESHOLD = 6


@dataclass
class MisconceptionCluster:
    """一个反复出现的错误心智模型。"""

    label: str
    occurrences: int
    skills: list[str]
    first_seen: datetime
    last_seen: datetime
    principle_ids: list[int] = field(default_factory=list)

    @property
    def cross_domain(self) -> bool:
        """横跨两个以上不同技能点。

        这是整个画像里最有说服力的信号：同一个错误心智模型在互不相关的领域里
        重复出现，说明问题不在某个知识点上，而在这个人的思维方式里——这是通用
        对话式 AI 结构上给不出的判断，因为它不保存你的历史。
        """
        return len(set(self.skills)) >= 2


@dataclass
class LearnerProfile:
    total_skills: int
    mastered_skills: int
    available_skills: int
    total_audits: int
    passed_audits: int
    failed_audits: int
    clusters: list[MisconceptionCluster]
    health: float | None
    sanity: float | None
    focus_score: int | None

    @property
    def pass_rate(self) -> float | None:
        resolved = self.passed_audits + self.failed_audits
        return self.passed_audits / resolved if resolved else None


def _load_misconception_rows(session: Session) -> list[tuple[Principle, str]]:
    """取出所有诊断过 misconception 的原则，连同它们各自来自哪个技能点。

    用 outer join：source_session_id 指向的会话理论上一定存在，但真要断了链
    （历史数据、测试夹具直接造的原则），丢掉整条记录比显示一个"未知技能"更糟。
    """
    rows = session.exec(
        select(Principle, SkillNode.title)
        .outerjoin(AuditSession, AuditSession.id == Principle.source_session_id)
        .outerjoin(SkillNode, SkillNode.id == AuditSession.skill_id)
        .where(Principle.misconception.is_not(None))
        .order_by(Principle.created_at)
    ).all()
    return [(p, title or "未知技能") for p, title in rows if p.misconception]


def cluster_misconceptions(session: Session) -> list[MisconceptionCluster]:
    """把语义重复的 misconception 归并成簇，按发作次数降序返回。

    单链聚类（single-linkage）：只要和簇里**任意一条**足够相似就并入同一簇。选它
    而不是"必须和簇内所有条都相似"，是因为同一个心智模型在不同技能点下的措辞会
    漂移——"以为相关就是因果"和"把同时发生当成谁导致谁"讲的是一回事，但两者的字面
    重叠可能不够，中间那条措辞居中的记录会把它们连起来。这正是单链要的效果。

    实现上是朴素的两两比较 + 并查集，O(n²)。原则表在单用户规模下只有几十条，和
    retrieval.find_relevant_principles 的全表扫描是同一个量级的取舍：先要正确和
    可读，等真的慢了再说。
    """
    rows = _load_misconception_rows(session)
    n = len(rows)
    if n == 0:
        return []

    parent = list(range(n))

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a: int, b: int) -> None:
        ra, rb = find(a), find(b)
        if ra != rb:
            # 总是并到更小的下标上，让每个簇的根就是它最早出现的那条记录
            # （rows 按 created_at 升序），下面直接拿它当 label。
            parent[max(ra, rb)] = min(ra, rb)

    for i in range(n):
        for j in range(i + 1, n):
            if relevance_score(rows[i][0].misconception, rows[j][0].misconception) >= CLUSTER_THRESHOLD:
                union(i, j)

    grouped: dict[int, list[int]] = {}
    for i in range(n):
        grouped.setdefault(find(i), []).append(i)

    clusters: list[MisconceptionCluster] = []
    for root, members in grouped.items():
        principles = [rows[i][0] for i in members]
        skills = [rows[i][1] for i in members]
        timestamps = [as_utc(p.created_at) for p in principles]
        clusters.append(
            MisconceptionCluster(
                label=rows[root][0].misconception,
                occurrences=len(members),
                skills=skills,
                first_seen=min(timestamps),
                last_seen=max(timestamps),
                principle_ids=[p.id for p in principles],
            )
        )

    # 跨领域的排最前面，其次按发作次数——用户最该先看到的是"这个毛病你到处都在犯"，
    # 而不是"这个毛病你犯得最多"。
    clusters.sort(key=lambda c: (c.cross_domain, c.occurrences, c.last_seen), reverse=True)
    return clusters


def build_profile(session: Session) -> LearnerProfile:
    """聚合出完整画像。零 LLM 调用，可以随便刷。"""
    skills = session.exec(select(SkillNode)).all()
    audits = session.exec(select(AuditSession)).all()
    vitality = session.exec(select(VitalityState)).first()
    focus = session.exec(select(FocusSession).order_by(FocusSession.started_at.desc())).first()

    return LearnerProfile(
        total_skills=len(skills),
        mastered_skills=sum(1 for s in skills if s.status == SkillStatus.mastered),
        available_skills=sum(1 for s in skills if s.status == SkillStatus.available),
        total_audits=len(audits),
        passed_audits=sum(1 for a in audits if a.status == AuditStatus.passed),
        failed_audits=sum(1 for a in audits if a.status == AuditStatus.failed),
        clusters=cluster_misconceptions(session),
        health=vitality.health if vitality else None,
        sanity=vitality.sanity if vitality else None,
        focus_score=focus.focus_score if focus else None,
    )
