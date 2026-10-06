"""数据库模型（plan 第 5 节）：约束、带时区的时间戳、启动与旧库处理。"""

from datetime import date, datetime, timedelta, timezone

import pytest
from sqlalchemy import inspect, text
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, SQLModel, create_engine, select
from sqlmodel.pool import StaticPool

import app.db as app_db
from app.models import (
    AuditSession,
    AuditTurn,
    BanditArm,
    CheckInSource,
    Course,
    DailyCheckIn,
    EdgeKind,
    NarratorBriefing,
    NodePosition,
    NodeType,
    Principle,
    PrincipleLink,
    RewardEvent,
    SearchPlan,
    SkillEdge,
    SkillNode,
    SkillStatus,
    StudyPlan,
    TurnRole,
)
from tests.helpers import make_audit, make_course, make_skill


def new_engine():
    return create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)


@pytest.fixture(name="session")
def session_fixture():
    engine = new_engine()
    SQLModel.metadata.create_all(engine)
    with Session(engine) as session:
        yield session


def test_the_tables_are_exactly_the_planned_ones():
    assert set(SQLModel.metadata.tables) == {
        "course", "skillnode", "skilledge", "auditsession", "auditturn", "principle", "principlelink",
        "dailycheckin", "rewardevent", "narratorbriefing", "studyplan", "searchplan", "banditarm", "chatmessage", "upload",
        "profile", "journalentry", "goal",
    }


def test_skill_node_has_no_parent_id():
    columns = {c.name for c in SkillNode.__table__.columns}

    assert "parent_id" not in columns
    assert columns == {"id", "course_id", "slug", "title", "description", "status", "node_type", "mastery_score"}


def test_every_timestamp_comes_back_timezone_aware_utc(session):
    course = make_course(session)
    skill = make_skill(session, course, "s")
    audit = make_audit(session, skill)
    rows = [
        course,
        SkillEdge(from_id=skill.id, to_id=skill.id, kind=EdgeKind.requires),
        audit,
        AuditTurn(session_id=audit.id, role=TurnRole.user, content="c"),
        Principle(title="t", body="b", source_session_id=audit.id),
        PrincipleLink(principle_id=1, target_kind="skill", target_id=1, kind="related", reason="r"),
        RewardEvent(session_id=audit.id, amount=1, multiplier=1.0),
        DailyCheckIn(date=date(2026, 10, 5)),
        NarratorBriefing(narrative="n"),
        StudyPlan(steps_json="[]", context_json="{}"),
        SearchPlan(skill_id=skill.id, gap="g", queries_json="[]", items_json="[]"),
    ]
    session.add_all(rows[1:])
    session.commit()

    for row in rows:
        session.refresh(row)
        stamp = getattr(row, "created_at", None) or row.generated_at
        assert stamp.tzinfo is not None, type(row).__name__
        assert stamp.utcoffset() == timedelta(0), type(row).__name__


def test_a_timestamp_in_another_zone_is_stored_as_the_same_instant_in_utc(session):
    kst = timezone(timedelta(hours=9))
    course = Course(topic="t", created_at=datetime(2026, 10, 5, 9, 0, tzinfo=kst))
    session.add(course)
    session.commit()
    session.refresh(course)

    assert course.created_at == datetime(2026, 10, 5, 0, 0, tzinfo=timezone.utc)
    assert course.created_at.utcoffset() == timedelta(0)


def test_a_naive_timestamp_is_taken_to_be_utc(session):
    course = Course(topic="t", created_at=datetime(2026, 10, 5, 3, 0))
    session.add(course)
    session.commit()
    session.refresh(course)

    assert course.created_at == datetime(2026, 10, 5, 3, 0, tzinfo=timezone.utc)


def test_slug_is_unique_within_a_course_but_not_across_courses(session):
    first = make_course(session)
    second = make_course(session)
    make_skill(session, first, "same-slug")
    make_skill(session, second, "same-slug")  # fine

    with pytest.raises(IntegrityError):
        make_skill(session, first, "same-slug")


def test_an_edge_is_unique_per_kind_but_the_same_pair_may_have_both_kinds(session):
    course = make_course(session)
    a = make_skill(session, course, "a")
    b = make_skill(session, course, "b")
    session.add(SkillEdge(from_id=a.id, to_id=b.id, kind=EdgeKind.contains, is_primary=True))
    session.add(SkillEdge(from_id=a.id, to_id=b.id, kind=EdgeKind.requires, reason="r"))
    session.commit()

    session.add(SkillEdge(from_id=a.id, to_id=b.id, kind=EdgeKind.contains, is_primary=False))
    with pytest.raises(IntegrityError):
        session.commit()


def test_skill_edge_indexes_exist():
    names = {index.name for index in SkillEdge.__table__.indexes}

    assert {"ix_skilledge_to_kind", "ix_skilledge_from_kind"} <= names


def test_one_check_in_per_date(session):
    session.add(DailyCheckIn(date=date(2026, 10, 5), sleep_hours=6))
    session.commit()

    session.add(DailyCheckIn(date=date(2026, 10, 5), sleep_hours=7))
    with pytest.raises(IntegrityError):
        session.commit()


def test_check_in_roundtrip_with_all_fields(session):
    session.add(
        DailyCheckIn(
            date=date(2026, 10, 5),
            sleep_hours=6,
            exercised=False,
            diet_note="lunch: ramen",
            focus=3,
            stress=2,
            transcript="I slept about six hours ...",
            source=CheckInSource.voice,
        )
    )
    session.commit()

    saved = session.exec(select(DailyCheckIn)).one()
    assert (saved.sleep_hours, saved.exercised, saved.diet_note, saved.focus, saved.stress) == (6, False, "lunch: ramen", 3, 2)
    assert saved.source == CheckInSource.voice
    assert saved.transcript.startswith("I slept")


def test_check_in_fields_may_all_be_empty(session):
    session.add(DailyCheckIn(date=date(2026, 10, 6)))
    session.commit()

    saved = session.exec(select(DailyCheckIn)).one()
    assert (saved.sleep_hours, saved.exercised, saved.diet_note, saved.focus, saved.stress, saved.transcript) == (None,) * 6
    assert saved.source == CheckInSource.manual


def test_audit_session_defaults_and_snapshot(session):
    skill = make_skill(session, make_course(session), "s")
    audit = AuditSession(skill_id=skill.id, node_position=NodePosition.branch, max_turns=16)
    session.add(audit)
    session.commit()
    session.refresh(audit)

    assert audit.node_position == NodePosition.branch
    assert audit.challenged is False
    assert (audit.score, audit.gaps_json, audit.comment) == (None, None, None)
    assert audit.max_turns == 16


def test_skill_node_defaults(session):
    node = SkillNode(course_id=make_course(session).id, slug="s", title="t", description="d")
    session.add(node)
    session.commit()
    session.refresh(node)

    assert (node.status, node.node_type, node.mastery_score) == (SkillStatus.locked, NodeType.concept, None)


def test_reward_and_bandit_roundtrip(session):
    audit = make_audit(session, make_skill(session, make_course(session), "s"))
    session.add(RewardEvent(session_id=audit.id, amount=42, multiplier=1.5))
    session.add(BanditArm(context_bucket="mid", tier="easy"))
    session.commit()

    reward = session.exec(select(RewardEvent)).one()
    arm = session.exec(select(BanditArm)).one()
    assert (reward.amount, reward.multiplier) == (42, 1.5)
    assert (arm.alpha, arm.beta) == (1.0, 1.0)


# ---------------------------------------------------------------- 启动与旧库


def test_init_db_creates_every_table_on_a_fresh_database(monkeypatch):
    engine = new_engine()
    monkeypatch.setattr(app_db, "engine", engine)

    app_db.init_db()
    app_db.init_db()  # and is happy to run twice

    assert set(inspect(engine).get_table_names()) == set(SQLModel.metadata.tables)


def test_the_app_starts_on_a_fresh_empty_database(client, client_engine):
    # The lifespan ran init_db() against an engine that already had its tables; nothing is seeded.
    assert client.get("/api/health").json() == {"status": "ok", "llm_provider": "mock"}
    assert client.get("/api/courses").json() == []
    assert client.get("/api/skills").json() == []


def test_init_db_refuses_a_database_from_before_courses_existed(monkeypatch):
    engine = new_engine()
    with engine.begin() as conn:
        conn.execute(text("CREATE TABLE skillnode (id INTEGER PRIMARY KEY, slug TEXT, title TEXT, parent_id INTEGER)"))
        conn.execute(text("INSERT INTO skillnode (slug, title) VALUES ('big-o', 'Big-O')"))
    monkeypatch.setattr(app_db, "engine", engine)

    with pytest.raises(RuntimeError, match="older version"):
        app_db.init_db()

    # And it did not half-migrate the file: nothing was added next to the old table.
    assert inspect(engine).get_table_names() == ["skillnode"]
    with engine.connect() as conn:
        assert conn.execute(text("SELECT COUNT(*) FROM skillnode")).scalar() == 1


def test_init_db_appends_a_missing_nullable_column(monkeypatch):
    engine = new_engine()
    SQLModel.metadata.create_all(engine)
    with engine.begin() as conn:
        conn.execute(text("ALTER TABLE course DROP COLUMN source_url"))
    assert "source_url" not in {c["name"] for c in inspect(engine).get_columns("course")}
    monkeypatch.setattr(app_db, "engine", engine)

    app_db.init_db()

    assert "source_url" in {c["name"] for c in inspect(engine).get_columns("course")}


def test_get_session_follows_the_patched_engine(client_engine):
    session = next(app_db.get_session())
    try:
        assert session.get_bind() is client_engine
    finally:
        session.close()
