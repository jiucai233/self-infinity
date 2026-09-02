"""misconception 聚类与学习者画像。

聚类是 Narrator 首屏的核心内容——"你的 N 个反复发作的思维缺陷，其中一个横跨了
互不相关的领域"这句话全靠它算出来，所以这里测得比别处细。
"""

from datetime import timedelta

from sqlmodel import Session, SQLModel, create_engine
from sqlmodel.pool import StaticPool

from app.models import (
    AuditSession,
    AuditStatus,
    Principle,
    SkillNode,
    SkillStatus,
    utcnow,
)
from app.services.profile import build_profile, cluster_misconceptions

# 刻意构造的单链传递性夹具（重叠分见 relevance_score）：
#   A~B = 8（链接）   B~C = 6（链接）   A~C = 0（不链接）
# 单链聚类必须靠 B 把 A 和 C 连成一簇——这正是"同一个心智模型换个说法"的真实形态。
A = "以为相关性就是因果关系"
B = "以为相关性就是因果，忽略了混淆变量"
C = "忽略了混淆变量的存在"
UNRELATED = "以为记住结论就等于理解了机制"


def _make_session() -> Session:
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    SQLModel.metadata.create_all(engine)
    return Session(engine)


def _add_failure(session: Session, skill_title: str, misconception: str, minutes_ago: int = 0) -> Principle:
    """造一条"在某技能点上失败并诊断出某 misconception"的完整链路。"""
    skill = session.exec(
        SkillNode.__table__.select().where(SkillNode.__table__.c.title == skill_title)
    ).first()
    if skill is None:
        skill = SkillNode(
            slug=f"s{abs(hash(skill_title)) % 10000}",
            title=skill_title,
            description=f"{skill_title}的说明",
            status=SkillStatus.available,
        )
        session.add(skill)
        session.flush()
        skill_id = skill.id
    else:
        skill_id = skill.id

    audit = AuditSession(skill_id=skill_id, status=AuditStatus.failed)
    session.add(audit)
    session.flush()

    principle = Principle(
        title="原则",
        body="当我再遇到时，我将…",
        misconception=misconception,
        source_session_id=audit.id,
        created_at=utcnow() - timedelta(minutes=minutes_ago),
    )
    session.add(principle)
    session.commit()
    return principle


def test_empty_library_yields_no_clusters():
    assert cluster_misconceptions(_make_session()) == []


def test_similar_misconceptions_collapse_into_one_cluster():
    session = _make_session()
    _add_failure(session, "统计学", A, minutes_ago=30)
    _add_failure(session, "投资", B, minutes_ago=10)

    clusters = cluster_misconceptions(session)

    assert len(clusters) == 1
    assert clusters[0].occurrences == 2


def test_unrelated_misconceptions_stay_separate():
    session = _make_session()
    _add_failure(session, "统计学", A)
    _add_failure(session, "算法", UNRELATED)

    assert len(cluster_misconceptions(session)) == 2


def test_single_linkage_is_transitive():
    """A 和 C 彼此不相似，但都相似于 B —— 单链必须把三条并成一簇。

    这条是选单链而非全链的理由：同一个心智模型在不同技能点下措辞会漂移，
    中间那条措辞居中的记录负责把两端连起来。
    """
    session = _make_session()
    _add_failure(session, "统计学", A, minutes_ago=30)
    _add_failure(session, "投资", B, minutes_ago=20)
    _add_failure(session, "实验设计", C, minutes_ago=10)

    clusters = cluster_misconceptions(session)

    assert len(clusters) == 1
    assert clusters[0].occurrences == 3


def test_cross_domain_flag_needs_two_different_skills():
    session = _make_session()
    _add_failure(session, "统计学", A, minutes_ago=30)
    _add_failure(session, "投资", B, minutes_ago=10)

    cluster = cluster_misconceptions(session)[0]

    assert cluster.cross_domain is True
    assert set(cluster.skills) == {"统计学", "投资"}


def test_repeats_within_one_skill_are_not_cross_domain():
    """同一个技能点上栽两次是"没学会"，不是"思维方式有问题"——不该打跨领域标记。"""
    session = _make_session()
    _add_failure(session, "统计学", A, minutes_ago=30)
    _add_failure(session, "统计学", B, minutes_ago=10)

    cluster = cluster_misconceptions(session)[0]

    assert cluster.occurrences == 2
    assert cluster.cross_domain is False


def test_cross_domain_clusters_rank_first():
    """跨领域的排在更高频但单领域的前面——"到处都在犯"比"犯得多"更该先看见。"""
    session = _make_session()
    # 单领域但发作 3 次
    for i in range(3):
        _add_failure(session, "算法", UNRELATED, minutes_ago=50 - i)
    # 跨领域但只发作 2 次
    _add_failure(session, "统计学", A, minutes_ago=20)
    _add_failure(session, "投资", B, minutes_ago=10)

    clusters = cluster_misconceptions(session)

    assert len(clusters) == 2
    assert clusters[0].cross_domain is True
    assert clusters[0].occurrences == 2
    assert clusters[1].occurrences == 3


def test_cluster_label_comes_from_the_earliest_record():
    session = _make_session()
    _add_failure(session, "统计学", A, minutes_ago=30)
    _add_failure(session, "投资", B, minutes_ago=10)

    assert cluster_misconceptions(session)[0].label == A


def test_orphaned_principle_still_appears():
    """source_session_id 断链时不丢记录，只是技能点显示为未知。"""
    session = _make_session()
    session.add(Principle(title="孤儿", body="…", misconception=A, source_session_id=999))
    session.commit()

    clusters = cluster_misconceptions(session)

    assert len(clusters) == 1
    assert clusters[0].skills == ["未知技能"]


def test_build_profile_counts_skills_and_audits():
    session = _make_session()
    _add_failure(session, "统计学", A)
    session.add(AuditSession(skill_id=1, status=AuditStatus.passed))
    session.commit()

    profile = build_profile(session)

    assert profile.total_skills == 1
    assert profile.total_audits == 2
    assert profile.passed_audits == 1
    assert profile.failed_audits == 1
    assert profile.pass_rate == 0.5
    assert len(profile.clusters) == 1


def test_pass_rate_is_none_before_any_verdict():
    assert build_profile(_make_session()).pass_rate is None
