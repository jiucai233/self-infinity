"""Workout tracker (contract #54): records, a said-line reader, routines, a summary, CSV / XLSX.

What the feature does:

- A *workout* is one exercise on one calendar day (sets, reps, weight, minutes, km).
- The *catalog* is a fixed list of about 30 common exercises with names in English, Chinese
  and Korean; it gives each exercise a category and a unit (reps / time / distance).
- A *said line* such as "3x12 bench press 60kg and 5km run" is split into pieces, and every
  piece is read by rules (regular expressions plus the catalog). Only the pieces the rules
  cannot read may go to an LLM, and only when a real provider is configured.
- A *routine* is a named list of exercises planned on some weekdays; checking an item off for
  a day creates a workout.
- The *summary* counts workouts over a window, the current and best streak of days, and XP.
- CSV and XLSX export and import use the same nine columns.

Dates are plain `datetime.date` values in APP_TIMEZONE; "today" always comes from
`app.utils.local_today()` so tests can freeze it.
"""

import csv
import io
import json
import logging
import re
from datetime import date, datetime, timedelta

from openpyxl import Workbook, load_workbook
from sqlmodel import Session, select

from app import utils
from app.i18n import current_language
from app.llm.base import LLMProvider, Message, agent_tag, complete_with_json_retry, strip_code_fence
from app.models import Routine, Workout

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------- limits

CATEGORIES = ["strength", "cardio", "flexibility", "sports", "other"]

# field -> (lowest, highest), both inclusive. The API schemas read this table too.
BOUNDS: dict[str, tuple[float, float]] = {
    "sets": (1, 50),
    "reps": (1, 1000),
    "weight_kg": (0, 500),
    "duration_min": (1, 600),
    "distance_km": (0.1, 300),
}
NUMBER_FIELDS = ("sets", "reps", "weight_kg", "duration_min", "distance_km")
# At least one of these must be set; weight alone says nothing about an exercise.
COUNT_FIELDS = ("sets", "reps", "duration_min", "distance_km")
MAX_NAME = 40
MAX_NOTE = 200

XP_PER_WORKOUT = 10
XP_FULL_ROUTINE_DAY = 20
DEFAULT_LIST_DAYS = 30
MAX_IMPORT_BYTES = 2 * 1024 * 1024

# Columns of the export, and of an import file (header row required).
COLUMNS = ["date", "exercise", "category", "sets", "reps", "weight_kg", "duration_min", "distance_km", "note"]

# ---------------------------------------------------------------- the catalog

# One tuple per exercise: (key, category, unit, English name, Chinese name, Korean name, aliases).
# The aliases are other things people say, in any of the three languages; matching ignores case.
CATALOG: list[tuple[str, str, str, str, str, str, tuple[str, ...]]] = [
    ("squat", "strength", "reps", "Squat", "深蹲", "스쿼트", ("squats", "스쿼트", "蹲")),
    ("push_up", "strength", "reps", "Push-up", "俯卧撑", "푸시업", ("push-up", "pushup", "push up", "press-up", "팔굽혀펴기", "腕立て")),
    ("pull_up", "strength", "reps", "Pull-up", "引体向上", "풀업", ("pull-up", "pullup", "pull up", "chin-up", "턱걸이")),
    ("bench_press", "strength", "reps", "Bench press", "卧推", "벤치프레스", ("bench press", "bench", "벤치", "平板卧推")),
    ("deadlift", "strength", "reps", "Deadlift", "硬拉", "데드리프트", ("dead lift", "데드")),
    ("lunge", "strength", "reps", "Lunge", "箭步蹲", "런지", ("弓步", "弓步蹲")),
    ("sit_up", "strength", "reps", "Sit-up", "仰卧起坐", "윗몸일으키기", ("sit-up", "situp", "sit up", "복근")),
    ("crunch", "strength", "reps", "Crunch", "卷腹", "크런치", ()),
    ("shoulder_press", "strength", "reps", "Shoulder press", "肩上推举", "숄더프레스", ("overhead press", "肩推")),
    ("bicep_curl", "strength", "reps", "Biceps curl", "哑铃弯举", "바이셉 컬", ("bicep curl", "biceps curl", "curl", "弯举", "덤벨컬", "바벨컬")),
    ("dip", "strength", "reps", "Dip", "双杠臂屈伸", "딥스", ("dips", "딥")),
    ("burpee", "strength", "reps", "Burpee", "波比跳", "버피", ("버피테스트", "波比")),
    ("leg_press", "strength", "reps", "Leg press", "腿举", "레그프레스", ()),
    ("lat_pulldown", "strength", "reps", "Lat pulldown", "高位下拉", "랫풀다운", ("pulldown", "렛풀다운")),
    ("plank", "strength", "time", "Plank", "平板支撑", "플랭크", ("平板",)),
    ("running", "cardio", "distance", "Running", "跑步", "러닝", ("run", "jog", "jogging", "런닝", "달리기", "조깅", "慢跑", "跑")),
    ("walking", "cardio", "distance", "Walking", "步行", "걷기", ("walk", "산책", "散步", "走路", "快走")),
    ("cycling", "cardio", "distance", "Cycling", "骑行", "사이클", ("cycle", "bike", "biking", "자전거", "싸이클", "骑车", "单车", "骑自行车")),
    ("swimming", "cardio", "distance", "Swimming", "游泳", "수영", ("swim",)),
    ("hiking", "cardio", "distance", "Hiking", "爬山", "등산", ("hike", "徒步")),
    ("jump_rope", "cardio", "time", "Jump rope", "跳绳", "줄넘기", ("skipping", "skip rope")),
    ("rowing", "cardio", "time", "Rowing", "划船机", "로잉", ("row", "rowing machine", "划船")),
    ("stairs", "cardio", "time", "Stair climbing", "爬楼梯", "계단 오르기", ("stairs", "계단오르기", "계단", "爬楼")),
    ("stretching", "flexibility", "time", "Stretching", "拉伸", "스트레칭", ("stretch", "伸展")),
    ("yoga", "flexibility", "time", "Yoga", "瑜伽", "요가", ()),
    ("pilates", "flexibility", "time", "Pilates", "普拉提", "필라테스", ()),
    ("basketball", "sports", "time", "Basketball", "篮球", "농구", ()),
    ("soccer", "sports", "time", "Soccer", "足球", "축구", ("football",)),
    ("badminton", "sports", "time", "Badminton", "羽毛球", "배드민턴", ()),
    ("tennis", "sports", "time", "Tennis", "网球", "테니스", ()),
    ("table_tennis", "sports", "time", "Table tennis", "乒乓球", "탁구", ("ping pong", "pingpong")),
]

# key -> catalog tuple, for quick lookups by key.
CATALOG_BY_KEY: dict[str, tuple] = {entry[0]: entry for entry in CATALOG}
_NAME_COLUMN = {"en": 3, "zh": 4, "ko": 5}


def catalog_name(key: str, language: str) -> str:
    """The catalog name of exercise [key] in [language] (en / zh / ko; anything else is English)."""
    return CATALOG_BY_KEY[key][_NAME_COLUMN.get(language, 3)]


def catalog_listing() -> dict:
    """Body of GET /api/workouts/catalog: categories and exercises named in the request language."""
    language = current_language()
    exercises = [
        {"key": key, "name": catalog_name(key, language), "category": category, "unit": unit}
        for key, category, unit, *_ in CATALOG
    ]
    return {"categories": list(CATEGORIES), "exercises": exercises}


def _build_alias_table() -> list[tuple[str, str]]:
    """Every name and alias of every exercise in all three languages as (alias, key), longest first,
    so "bench press" is tried before "bench" and "running" before "run"."""
    pairs: list[tuple[str, str]] = []
    for key, _category, _unit, en, zh, ko, aliases in CATALOG:
        for alias in (en, zh, ko, *aliases):
            pairs.append((alias.lower(), key))
    pairs.sort(key=lambda pair: len(pair[0]), reverse=True)
    return pairs


ALIASES = _build_alias_table()


def _alias_in(alias: str, text: str) -> bool:
    """Whether [alias] occurs in lower-cased [text]. Latin aliases must stand as whole words
    (an optional plural s is fine); Korean and Chinese have no spaces, so a substring will do."""
    if alias.isascii():
        pattern = r"(?<![a-z])" + re.escape(alias) + r"(?:e?s)?(?![a-z])"
        return re.search(pattern, text) is not None
    return alias in text


def match_catalog(text: str) -> str | None:
    """The key of the first (longest) catalog name or alias found in [text], else None."""
    lowered = text.lower()
    for alias, key in ALIASES:
        if _alias_in(alias, lowered):
            return key
    return None


def resolve_exercise(name: str, key: str | None, category: str | None) -> tuple[str, str | None, str]:
    """Settle (name, exercise_key, category) of a record.

    A known [key] is kept; an unknown one is dropped. Without a key the whole [name] is looked up
    in the catalog. The category given wins; otherwise it comes from the catalog, else "other".
    The name stays as entered.
    """
    name = name.strip()
    if key not in CATALOG_BY_KEY:
        key = None
    if key is None:
        # Only an exact name counts here: "Squat jumps" is its own exercise.
        lowered = name.lower()
        for alias, candidate in ALIASES:
            if alias == lowered:
                key = candidate
                break
    if category not in CATEGORIES:
        category = CATALOG_BY_KEY[key][1] if key else "other"
    return name, key, category


# ---------------------------------------------------------------- checking numbers


def check_numbers(values: dict) -> str | None:
    """Why [values] (a dict of the workout number fields) cannot be a record, or None if it can."""
    for field in NUMBER_FIELDS:
        value = values.get(field)
        if value is None:
            continue
        low, high = BOUNDS[field]
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not low <= value <= high:
            return f"{field} must be between {low} and {high}"
    if all(values.get(field) is None for field in COUNT_FIELDS):
        return "set at least one of sets, reps, duration_min, distance_km"
    return None


# ---------------------------------------------------------------- reading a said line

# Words that move the whole line to the day before.
YESTERDAY_WORDS = ["yesterday", "어제", "昨天", "昨日"]
# Words that only say "today" or fill the sentence; they are not part of an exercise name.
FILLER_WORDS = ["today", "오늘", "今天", "i did", "i ran", "did", "했어요", "했어", "했다", "했습니다", "做了", "练了", "for", "of"]

# Pieces are separated by these (a Latin " and " needs its spaces, the CJK joiners do not).
_SPLIT_RE = re.compile(r"[,;、，；\n]|\s+and\s+|\s+그리고\s+|(?<=\S)하고\s+|和", re.IGNORECASE)

_NUM = r"(\d+(?:\.\d+)?)"
# Each unit pattern captures one number. Longer unit words come first in each alternation.
_SETS_RE = re.compile(_NUM + r"\s*(?:세트|sets?\b|组|組)", re.IGNORECASE)
_REPS_RE = re.compile(_NUM + r"\s*(?:reps?\b|repetitions?\b|회|개|次|个|個|下)", re.IGNORECASE)
_TIMES_RE = re.compile(r"(\d+)\s*[x×*]\s*(\d+)", re.IGNORECASE)
_WEIGHT_RE = re.compile(_NUM + r"\s*(?:kgs?\b|킬로그램|킬로(?!미터)|公斤|千克)", re.IGNORECASE)
_HOURS_RE = re.compile(_NUM + r"\s*(?:hours?\b|hrs?\b|h\b|시간|小时|小時)", re.IGNORECASE)
_MINUTES_RE = re.compile(_NUM + r"\s*(?:minutes?\b|mins?\b|분|分钟|分鐘|分)", re.IGNORECASE)
_KM_RE = re.compile(_NUM + r"\s*(?:km\b|킬로미터|키로|公里|千米)", re.IGNORECASE)
_BARE_NUMBER_RE = re.compile(r"(?<![\w.])(\d+(?:\.\d+)?)(?![\w.])")


def split_pieces(text: str) -> list[str]:
    """Split a said line into its non-empty pieces (see _SPLIT_RE for the separators)."""
    return [piece.strip() for piece in _SPLIT_RE.split(text) if piece and piece.strip()]


def extract_day(text: str, base: date) -> tuple[str, date]:
    """Remove yesterday words from [text]; return (the rest, the day the line is about)."""
    day = base
    lowered = text.lower()
    for word in YESTERDAY_WORDS:
        if word in lowered:
            day = base - timedelta(days=1)
            # Cut every spelling of the word out, whatever its case.
            text = re.sub(re.escape(word), " ", text, flags=re.IGNORECASE)
            lowered = text.lower()
    return text, day


def _take(pattern: re.Pattern, text: str) -> tuple[float | None, str]:
    """Find the first match of [pattern]: return (its first number, the text without it)."""
    match = pattern.search(text)
    if match is None:
        return None, text
    return float(match.group(1)), text[: match.start()] + " " + text[match.end():]


def _whole(value: float | None) -> int | None:
    return None if value is None else int(round(value))


def read_piece(piece: str) -> dict | None:
    """Read one piece of a said line into workout fields, or None when the rules cannot.

    The numbers are cut out of the text unit by unit; what is left is matched against the catalog.
    A piece with no catalog name but numbers keeps its own words as the exercise name.
    """
    rest = piece
    sets = reps = None
    times = _TIMES_RE.search(rest)
    if times:  # "3x12" means 3 sets of 12 reps
        sets, reps = int(times.group(1)), int(times.group(2))
        rest = rest[: times.start()] + " " + rest[times.end():]
    found_sets, rest = _take(_SETS_RE, rest)
    found_reps, rest = _take(_REPS_RE, rest)
    sets = _whole(found_sets) if found_sets is not None else sets
    reps = _whole(found_reps) if found_reps is not None else reps
    weight, rest = _take(_WEIGHT_RE, rest)
    hours, rest = _take(_HOURS_RE, rest)
    minutes, rest = _take(_MINUTES_RE, rest)
    km, rest = _take(_KM_RE, rest)

    duration = None
    if hours is not None or minutes is not None:
        duration = int(round((hours or 0) * 60 + (minutes or 0)))

    key = match_catalog(rest)
    if key is not None and CATALOG_BY_KEY[key][2] == "time" and duration is None:
        # A time exercise with a bare number: "plank 2" is two minutes.
        bare = _BARE_NUMBER_RE.search(rest)
        if bare:
            duration = int(round(float(bare.group(1))))

    if key is not None:
        name = catalog_name(key, current_language())
    else:
        name = _clean_words(rest)
        if not name:
            return None
    record = {
        "exercise": name[:MAX_NAME],
        "exercise_key": key,
        "sets": sets,
        "reps": reps,
        "weight_kg": weight,
        "duration_min": duration,
        "distance_km": km,
    }
    if check_numbers(record) is not None:
        return None
    return record


def _clean_words(text: str) -> str:
    """The words left of a piece once numbers and filler are gone, as one tidy string."""
    text = _BARE_NUMBER_RE.sub(" ", text)
    for word in FILLER_WORDS:
        text = re.sub(r"(?<![a-z])" + re.escape(word) + r"(?![a-z])", " ", text, flags=re.IGNORECASE)
    text = re.sub(r"[\s\W_]+", " ", text, flags=re.UNICODE)
    return text.strip()


def read_line(text: str, base: date) -> tuple[list[dict], list[str], date]:
    """Read a whole said line.

    Returns (records the rules read, pieces they could not read, the day of the line). Yesterday
    words move the day to the one before [base].
    """
    text, day = extract_day(text, base)
    records: list[dict] = []
    unread: list[str] = []
    for piece in split_pieces(text):
        record = read_piece(piece)
        if record is None:
            # Pieces made only of filler ("today") name nothing and are not worth reporting.
            if _clean_words(piece):
                unread.append(piece)
        else:
            records.append(record)
    return records, unread, day


# ---------------------------------------------------------------- LLM fallback for unread pieces

READER_PROMPT = (
    agent_tag("workout_reader")
    + """
Read workout records out of text pieces the user said. The pieces are numbered, in the next message.

For each piece that names an exercise with at least one number, give one record:
{{"piece": <number of the piece>, "exercise": "<short name>", "sets": int|null, "reps": int|null,
  "weight_kg": number|null, "duration_min": int|null, "distance_km": number|null}}

Limits: sets 1-50, reps 1-1000, weight_kg 0-500, duration_min 1-600 (convert hours to minutes),
distance_km 0.1-300. At least one of sets, reps, duration_min, distance_km must be given.
Skip pieces that are not a workout. Never invent a number the user did not say.

Output only JSON: {{"records": [...]}}
"""
)


def read_unread_with_llm(provider: LLMProvider | None, pieces: list[str]) -> tuple[list[dict], list[str]]:
    """Ask the LLM about the pieces the rules could not read, in one call.

    Returns (records read, pieces still unread). Does nothing without a provider or with the mock
    one. Whatever the model returns is checked by the same bounds; anything invalid, and any
    failure of the call itself, leaves the pieces unread.
    """
    if not pieces or provider is None or provider.name == "mock":
        return [], pieces
    numbered = "\n".join(f"{i}. {piece}" for i, piece in enumerate(pieces))
    messages: list[Message] = [
        {"role": "system", "content": READER_PROMPT},
        {"role": "user", "content": numbered},
    ]
    try:
        raw = complete_with_json_retry(provider, messages)
        data = json.loads(strip_code_fence(raw))
        items = data["records"]
        if not isinstance(items, list):
            raise ValueError("records is not a list")
    except Exception:
        logger.warning("workout reader failed, leaving the pieces unread", exc_info=True)
        return [], pieces

    records: list[dict] = []
    read_indexes: set[int] = set()
    for item in items:
        if not isinstance(item, dict) or not isinstance(item.get("piece"), int):
            continue
        index = item["piece"]
        name = item.get("exercise")
        if index in read_indexes or not 0 <= index < len(pieces) or not isinstance(name, str) or not name.strip():
            continue
        record = {field: item.get(field) for field in NUMBER_FIELDS}
        if check_numbers(record) is not None:
            continue
        key = match_catalog(name)
        record["exercise"] = (catalog_name(key, current_language()) if key else name.strip())[:MAX_NAME]
        record["exercise_key"] = key
        records.append(record)
        read_indexes.add(index)
    still_unread = [piece for i, piece in enumerate(pieces) if i not in read_indexes]
    return records, still_unread


# ---------------------------------------------------------------- workouts in the database


def add_workout(session: Session, day: date, values: dict, source: str = "manual", *, routine: tuple[int, int] | None = None) -> Workout:
    """Save one workout. [values] holds exercise, optional exercise_key / category / note and the
    number fields; [routine] is (routine id, item index) for a check-off."""
    name, key, category = resolve_exercise(values["exercise"], values.get("exercise_key"), values.get("category"))
    workout = Workout(
        date=day,
        exercise=name,
        exercise_key=key,
        category=category,
        note=values.get("note"),
        source=source,
        routine_id=routine[0] if routine else None,
        routine_item=routine[1] if routine else None,
        **{field: values.get(field) for field in NUMBER_FIELDS},
    )
    session.add(workout)
    session.commit()
    session.refresh(workout)
    return workout


def update_workout(workout: Workout, session: Session, day: date | None, values: dict) -> Workout:
    """Replace the fields of an existing workout (PUT); a missing date keeps the old one."""
    name, key, category = resolve_exercise(values["exercise"], values.get("exercise_key"), values.get("category"))
    workout.date = day or workout.date
    workout.exercise, workout.exercise_key, workout.category = name, key, category
    workout.note = values.get("note")
    for field in NUMBER_FIELDS:
        setattr(workout, field, values.get(field))
    session.add(workout)
    session.commit()
    session.refresh(workout)
    return workout


def list_workouts(session: Session, start: date | None, end: date | None) -> list[Workout]:
    """Workouts from [start] to [end] inclusive (default: the last 30 days), newest day first,
    then newest created first."""
    today = utils.local_today()
    end = end or today
    start = start or end - timedelta(days=DEFAULT_LIST_DAYS - 1)
    rows = session.exec(select(Workout).where(Workout.date >= start, Workout.date <= end)).all()
    rows.sort(key=lambda w: (w.date, w.created_at, w.id), reverse=True)
    return list(rows)


def say(session: Session, text: str, day: date | None, provider: LLMProvider | None = None) -> tuple[list[Workout], list[str]]:
    """Read a said line, save what was read (source "said"), return (saved workouts, unread pieces)."""
    base = day or utils.local_today()
    records, unread, line_day = read_line(text, base)
    if unread:
        extra, unread = read_unread_with_llm(provider, unread)
        records.extend(extra)
    saved = [add_workout(session, line_day, record, "said") for record in records]
    return saved, unread


# ---------------------------------------------------------------- streak, XP, summary


def current_streak(days_with_workouts: set[date], today: date) -> int:
    """Consecutive days with a workout, ending today, or yesterday when today has none yet."""
    day = today if today in days_with_workouts else today - timedelta(days=1)
    streak = 0
    while day in days_with_workouts:  # walk back one day at a time until a gap
        streak += 1
        day -= timedelta(days=1)
    return streak


def best_streak(days_with_workouts: set[date]) -> int:
    """The longest run of consecutive days with a workout, all time."""
    best = run = 0
    previous: date | None = None
    for day in sorted(days_with_workouts):
        run = run + 1 if previous is not None and day - previous == timedelta(days=1) else 1
        best = max(best, run)
        previous = day
    return best


def full_routine_days(routines: list[Routine], workouts: list[Workout]) -> int:
    """How many (routine, day) pairs were completed in full on a day the routine is scheduled."""
    # (routine id, day) -> the item indexes checked off that day
    checked: dict[tuple[int, date], set[int]] = {}
    for w in workouts:
        if w.routine_id is not None and w.routine_item is not None:
            checked.setdefault((w.routine_id, w.date), set()).add(w.routine_item)
    count = 0
    for routine in routines:
        weekdays = json.loads(routine.weekdays_json)
        wanted = set(range(len(json.loads(routine.items_json))))
        for (routine_id, day), items in checked.items():
            if routine_id == routine.id and day.weekday() in weekdays and wanted <= items:
                count += 1
    return count


def summary(session: Session, days: int) -> dict:
    """Body of GET /api/workouts/summary for a window of [days] days ending today."""
    today = utils.local_today()
    first = today - timedelta(days=days - 1)
    everything = list(session.exec(select(Workout)).all())
    routines = list(session.exec(select(Routine)).all())
    day_set = {w.date for w in everything}

    # One bucket per day of the window, oldest first, so empty days are in the list too.
    by_day = [
        {"date": first + timedelta(days=i), "minutes": 0, "workouts": 0} for i in range(days)
    ]
    buckets = {entry["date"]: entry for entry in by_day}
    by_category: dict[str, int] = {}
    in_window = 0
    for w in everything:
        if w.date in buckets:
            buckets[w.date]["workouts"] += 1
            buckets[w.date]["minutes"] += w.duration_min or 0
            by_category[w.category] = by_category.get(w.category, 0) + 1
            in_window += 1
    return {
        "days": days,
        "streak": current_streak(day_set, today),
        "best_streak": best_streak(day_set),
        "xp": XP_PER_WORKOUT * len(everything) + XP_FULL_ROUTINE_DAY * full_routine_days(routines, everything),
        "total_minutes": sum(entry["minutes"] for entry in by_day),
        "workouts": in_window,
        "by_category": by_category,
        "by_day": by_day,
    }


# ---------------------------------------------------------------- routines


def routine_view(routine: Routine) -> dict:
    """A Routine row as the API shows it (weekdays and items decoded)."""
    return {
        "id": routine.id,
        "name": routine.name,
        "weekdays": json.loads(routine.weekdays_json),
        "items": json.loads(routine.items_json),
        "created_at": routine.created_at,
    }


def _item_dict(item: dict) -> dict:
    """One routine item with its exercise resolved (key and category) and every field present."""
    name, key, category = resolve_exercise(item["exercise"], item.get("exercise_key"), item.get("category"))
    out = {"exercise": name, "exercise_key": key, "category": category}
    out.update({field: item.get(field) for field in NUMBER_FIELDS})
    return out


def save_routine(session: Session, routine: Routine | None, name: str, weekdays: list[int], items: list[dict]) -> Routine:
    """Create a routine, or replace [routine]'s contents when one is given."""
    routine = routine or Routine(name=name)
    routine.name = name
    routine.weekdays_json = json.dumps(sorted(set(weekdays)))
    routine.items_json = json.dumps([_item_dict(item) for item in items], ensure_ascii=False)
    session.add(routine)
    session.commit()
    session.refresh(routine)
    return routine


def routines_on(session: Session, day: date) -> list[dict]:
    """The routines scheduled on [day]'s weekday with each item's check-off state (GET /routines/day)."""
    checks = session.exec(select(Workout).where(Workout.date == day, Workout.routine_id.is_not(None))).all()
    # (routine id, item index) -> id of the workout that checked it off that day
    done_by = {(w.routine_id, w.routine_item): w.id for w in checks}
    result = []
    for routine in session.exec(select(Routine).order_by(Routine.id)).all():
        if day.weekday() not in json.loads(routine.weekdays_json):
            continue
        items = [
            {"index": i, "item": item, "workout_id": done_by.get((routine.id, i))}
            for i, item in enumerate(json.loads(routine.items_json))
        ]
        result.append({"routine": routine_view(routine), "items": items, "done": all(row["workout_id"] for row in items)})
    return result


def find_check(session: Session, routine_id: int, index: int, day: date) -> Workout | None:
    """The workout that checked item [index] of a routine off on [day], if any."""
    return session.exec(
        select(Workout).where(Workout.routine_id == routine_id, Workout.routine_item == index, Workout.date == day)
    ).first()


def check_item(session: Session, routine: Routine, index: int, day: date) -> Workout:
    """Check item [index] off for [day]: save a workout with the item's numbers (source "routine")."""
    item = json.loads(routine.items_json)[index]
    return add_workout(session, day, item, "routine", routine=(routine.id, index))


# ---------------------------------------------------------------- export


def _safe_text(value: str | None) -> str:
    """Text for a spreadsheet cell: one that starts like a formula gets a leading quote."""
    value = value or ""
    return "'" + value if value[:1] in ("=", "+", "@") else value


def _row_of(w: Workout) -> list:
    return [w.date.isoformat(), _safe_text(w.exercise), w.category, w.sets, w.reps, w.weight_kg, w.duration_min, w.distance_km, _safe_text(w.note)]


def _all_in_order(session: Session) -> list[Workout]:
    return list(session.exec(select(Workout).order_by(Workout.date, Workout.id)).all())


def export_csv(session: Session) -> bytes:
    """All workouts as CSV, UTF-8 with a BOM so Excel reads Korean and Chinese."""
    buffer = io.StringIO(newline="")
    writer = csv.writer(buffer)
    writer.writerow(COLUMNS)
    for w in _all_in_order(session):
        writer.writerow(["" if cell is None else cell for cell in _row_of(w)])
    return b"\xef\xbb\xbf" + buffer.getvalue().encode("utf-8")


def export_xlsx(session: Session) -> bytes:
    """All workouts as an XLSX file with one sheet."""
    book = Workbook()
    sheet = book.active
    sheet.title = "workouts"
    sheet.append(COLUMNS)
    for w in _all_in_order(session):
        sheet.append(_row_of(w))
    out = io.BytesIO()
    book.save(out)
    return out.getvalue()


# ---------------------------------------------------------------- import


def _decode_csv(data: bytes) -> str:
    """CSV bytes as text: UTF-8 (BOM or not), else the Korean Windows code page Excel may have used."""
    try:
        return data.decode("utf-8-sig")
    except UnicodeDecodeError:
        return data.decode("cp949")


def _read_rows(data: bytes) -> list[list]:
    """The rows of a CSV or XLSX file (XLSX files are zip files, which start with "PK").
    Raises ValueError when the file cannot be read."""
    if data[:2] == b"PK":
        try:
            book = load_workbook(io.BytesIO(data), read_only=True, data_only=True)
            return [list(row) for row in book.worksheets[0].iter_rows(values_only=True)]
        except Exception as exc:
            raise ValueError("not a readable .xlsx file") from exc
    try:
        return [row for row in csv.reader(io.StringIO(_decode_csv(data), newline=""))]
    except (UnicodeDecodeError, csv.Error) as exc:
        raise ValueError("not a readable .csv file") from exc


def _cell_text(value) -> str:
    """A cell as stripped text; dates become ISO strings, whole floats lose the ".0"."""
    if value is None:
        return ""
    if isinstance(value, datetime):
        return value.date().isoformat()
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    text = str(value).strip()
    return text[1:] if text[:1] == "'" and text[1:2] in ("=", "+", "@") else text


def _parse_number(text: str, field: str) -> float | None:
    if text == "":
        return None
    try:
        number = float(text)
    except ValueError:
        raise ValueError(f"{field} is not a number") from None
    return number


def _row_to_record(cells: dict[str, str]) -> tuple[date, dict]:
    """One import row (column name -> text) as (day, record). Raises ValueError with the reason."""
    try:
        day = date.fromisoformat(cells["date"][:10])
    except ValueError:
        raise ValueError("date must be YYYY-MM-DD") from None
    name = cells["exercise"]
    if not name or len(name) > MAX_NAME:
        raise ValueError(f"exercise must be 1 to {MAX_NAME} characters")
    category = cells["category"].lower() or None
    if category is not None and category not in CATEGORIES:
        raise ValueError("category is not one of " + ", ".join(CATEGORIES))
    if len(cells["note"]) > MAX_NOTE:
        raise ValueError(f"note is longer than {MAX_NOTE} characters")
    record: dict = {"exercise": name, "category": category, "note": cells["note"] or None}
    for field in NUMBER_FIELDS:
        number = _parse_number(cells[field], field)
        if number is not None and field in ("sets", "reps", "duration_min"):
            if not number.is_integer():
                raise ValueError(f"{field} must be a whole number")
            number = int(number)
        record[field] = number
    problem = check_numbers(record)
    if problem:
        raise ValueError(problem)
    return day, record


def _identity(day: date, record: dict) -> tuple:
    """What makes two workouts "the same" for the duplicate check."""
    return (day, record["exercise"], *(record.get(field) for field in NUMBER_FIELDS))


def import_file(session: Session, data: bytes) -> dict:
    """Import a CSV or XLSX file of workouts. Raises ValueError for an unreadable file or a missing
    header. Returns {"imported", "skipped", "errors"}; bad rows are listed, the rest imported."""
    rows = _read_rows(data)
    if not rows:
        raise ValueError("the file is empty")
    header = [_cell_text(cell).lower() for cell in rows[0]]
    if "date" not in header or "exercise" not in header:
        raise ValueError("the first row must be a header with the columns " + ", ".join(COLUMNS))
    position = {name: header.index(name) for name in COLUMNS if name in header}

    existing = {_identity(w.date, w.__dict__) for w in session.exec(select(Workout)).all()}
    imported = skipped = 0
    errors: list[dict] = []
    for number, row in enumerate(rows[1:], start=2):  # row numbers are the sheet's, header = 1
        cells = {name: _cell_text(row[position[name]]) if name in position and position[name] < len(row) else "" for name in COLUMNS}
        if not any(cells.values()):
            continue  # blank line
        try:
            day, record = _row_to_record(cells)
        except ValueError as exc:
            errors.append({"row": number, "reason": str(exc)})
            continue
        identity = _identity(day, record)
        if identity in existing:
            skipped += 1
            continue
        add_workout(session, day, record, "import")
        existing.add(identity)
        imported += 1
    return {"imported": imported, "skipped": skipped, "errors": errors}

