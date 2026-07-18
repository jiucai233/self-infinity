from datetime import date, datetime, timezone

from sqlmodel import Session, SQLModel, create_engine
from sqlmodel.pool import StaticPool

from app.models import DailyCheckIn, FocusSession, RewardEvent, VitalityState


def _engine():
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    SQLModel.metadata.create_all(engine)
    return engine


def test_reward_event_roundtrip():
    engine = _engine()
    with Session(engine) as session:
        event = RewardEvent(session_id=1, amount=42, multiplier=1.5)
        session.add(event)
        session.commit()
        session.refresh(event)

        fetched = session.get(RewardEvent, event.id)
        assert fetched is not None
        assert fetched.session_id == 1
        assert fetched.amount == 42
        assert fetched.multiplier == 1.5
        assert isinstance(fetched.created_at, datetime)


def test_daily_check_in_roundtrip():
    engine = _engine()
    with Session(engine) as session:
        check_in = DailyCheckIn(
            date=date(2026, 7, 19),
            spending_rating=2,
            activity_rating=3,
            eating_rating=1,
        )
        session.add(check_in)
        session.commit()
        session.refresh(check_in)

        fetched = session.get(DailyCheckIn, check_in.id)
        assert fetched is not None
        assert fetched.date == date(2026, 7, 19)
        assert fetched.spending_rating == 2
        assert fetched.activity_rating == 3
        assert fetched.eating_rating == 1


def test_vitality_state_roundtrip():
    engine = _engine()
    with Session(engine) as session:
        state = VitalityState(health=80.0, sanity=50.0, sanity_cap=100.0)
        session.add(state)
        session.commit()
        session.refresh(state)

        fetched = session.get(VitalityState, state.id)
        assert fetched is not None
        assert fetched.health == 80.0
        assert fetched.sanity == 50.0
        assert fetched.sanity_cap == 100.0
        assert isinstance(fetched.updated_at, datetime)


def test_focus_session_roundtrip():
    engine = _engine()
    with Session(engine) as session:
        focus = FocusSession(
            started_at=datetime.now(timezone.utc),
            source="audit_engagement",
        )
        session.add(focus)
        session.commit()
        session.refresh(focus)

        fetched = session.get(FocusSession, focus.id)
        assert fetched is not None
        assert fetched.ended_at is None
        assert fetched.focus_score is None
        assert fetched.source == "audit_engagement"
