import hashlib
import re
from datetime import date, datetime
from zoneinfo import ZoneInfo

from app.config import settings


def slugify(text: str) -> str:
    ascii_slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    if ascii_slug:
        return ascii_slug
    # 韩文、中文等非 ASCII 标题拿不到可用 slug 时，退化为内容哈希：唯一，并且跨进程稳定
    # （内置 hash() 每次启动都不同，不能用）。
    return f"node-{hashlib.sha1(text.encode()).hexdigest()[:8]}"


def local_now() -> datetime:
    """The current time in APP_TIMEZONE (KST by default), timezone-aware.

    The one clock the "what time is it for the user" code reads (local_today, the reflection
    windows). Tests freeze the clock by patching `app.utils.local_now`; callers must look it up
    as `utils.local_now()` (not `from app.utils import local_now`) for the patch to reach them.
    """
    return datetime.now(ZoneInfo(settings.app_timezone))


def local_today() -> date:
    """Today's calendar date in APP_TIMEZONE (KST by default).

    "One row per day" things (DailyCheckIn) must use this, not date.today():
    a check-in at 08:00 KST is already the next day in UTC.
    """
    return local_now().date()
