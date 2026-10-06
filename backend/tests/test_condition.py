"""Condition flag 与 audit pacing（plan 8.4 / 8.5）：最近 3 次签到，睡眠 < 6 小时或压力 ≥ 4 为 low。"""

from datetime import date, timedelta

import pytest
from sqlmodel import Session, SQLModel, create_engine
from sqlmodel.pool import StaticPool

from app.models import DailyCheckIn
from app.services.condition import audit_pacing, current_condition


@pytest.fixture(name="session")
def session_fixture():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    SQLModel.metadata.create_all(engine)
    with Session(engine) as session:
        yield session


def check_in(session: Session, day: int, sleep=None, stress=None) -> None:
    session.add(DailyCheckIn(date=date(2026, 10, 1) + timedelta(days=day), sleep_hours=sleep, stress=stress))
    session.commit()


def test_no_check_ins_is_unknown_and_paces_normally(session):
    condition = current_condition(session)

    assert (condition.days, condition.avg_sleep_hours, condition.avg_stress, condition.flag) == (0, None, None, "unknown")
    assert audit_pacing(session) == "normal"


def test_average_sleep_under_six_hours_is_low_and_paces_light(session):
    for day in range(3):
        check_in(session, day, sleep=5)

    condition = current_condition(session)

    assert (condition.days, condition.avg_sleep_hours, condition.flag) == (3, 5, "low")
    assert audit_pacing(session) == "light"


def test_exactly_six_hours_is_normal(session):
    for day in range(3):
        check_in(session, day, sleep=6)

    assert current_condition(session).flag == "normal"
    assert audit_pacing(session) == "normal"


def test_average_stress_of_four_or_more_is_low(session):
    for day, stress in enumerate((4, 4, 4)):
        check_in(session, day, sleep=8, stress=stress)

    assert current_condition(session).flag == "low"
    check_in(session, 3, sleep=8, stress=3)  # the window moves: (4, 4, 3) averages 3.67
    assert current_condition(session).flag == "normal"


def test_only_the_last_three_check_ins_count(session):
    check_in(session, 0, sleep=3)
    check_in(session, 1, sleep=3)  # these two fall out of the window
    for day in (2, 3, 4):
        check_in(session, day, sleep=8)

    condition = current_condition(session)

    assert (condition.days, condition.avg_sleep_hours, condition.flag) == (3, 8, "normal")


def test_the_window_is_the_latest_dates_not_the_latest_inserts(session):
    check_in(session, 10, sleep=8)
    check_in(session, 9, sleep=8)
    check_in(session, 8, sleep=8)
    check_in(session, 0, sleep=2)  # inserted last, but the oldest date

    assert current_condition(session).flag == "normal"


def test_empty_fields_are_left_out_of_the_averages_not_counted_as_zero(session):
    check_in(session, 0, sleep=7)
    check_in(session, 1, sleep=None, stress=None)
    check_in(session, 2, sleep=7, stress=None)

    condition = current_condition(session)

    assert (condition.avg_sleep_hours, condition.avg_stress, condition.flag) == (7, None, "normal")


def test_a_check_in_with_nothing_filled_in_is_normal_not_unknown(session):
    check_in(session, 0)

    condition = current_condition(session)

    assert (condition.days, condition.avg_sleep_hours, condition.avg_stress, condition.flag) == (1, None, None, "normal")


def test_one_short_night_among_three_averages_out(session):
    for day, sleep in enumerate((4, 7, 7)):
        check_in(session, day, sleep=sleep)

    assert current_condition(session).flag == "normal"  # (4 + 7 + 7) / 3 = 6
