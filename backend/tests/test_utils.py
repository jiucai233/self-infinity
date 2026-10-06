"""小工具：稳定的 slug、按 APP_TIMEZONE 计算的日历日期。"""

from datetime import date, datetime, timezone

from app.config import settings
from app.utils import local_today, slugify


def test_slugify_ascii_titles():
    assert slugify("Quadratic Equation!") == "quadratic-equation"
    assert slugify("  Big-O  ") == "big-o"


def test_slugify_falls_back_to_a_stable_hash_for_non_ascii_titles():
    first = slugify("二次方程式")

    assert first == slugify("二次方程式")  # stable (the built-in hash() is not, between runs)
    assert first.startswith("node-") and len(first) == len("node-") + 8
    assert first != slugify("二次関数")


class FrozenDatetime(datetime):
    """16:30 UTC on 2026-10-05, which is already 01:30 on the 6th in Seoul."""

    @classmethod
    def now(cls, tz=None):
        return datetime(2026, 10, 5, 16, 30, tzinfo=timezone.utc).astimezone(tz)


def test_local_today_uses_the_configured_timezone(monkeypatch):
    monkeypatch.setattr("app.utils.datetime", FrozenDatetime)

    monkeypatch.setattr(settings, "app_timezone", "Asia/Seoul")
    assert local_today() == date(2026, 10, 6)  # a check-in at 01:30 KST belongs to the 6th, not the 5th

    monkeypatch.setattr(settings, "app_timezone", "UTC")
    assert local_today() == date(2026, 10, 5)

    monkeypatch.setattr(settings, "app_timezone", "America/Los_Angeles")
    assert local_today() == date(2026, 10, 5)
