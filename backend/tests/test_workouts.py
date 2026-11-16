"""Workouts and routines (contract #54): records, the said-line reader, summary, routines, CSV / XLSX."""

import io
import json
from datetime import date, datetime
from zoneinfo import ZoneInfo

import pytest
from openpyxl import Workbook, load_workbook

from app import utils
from app.services import workouts as service

TODAY = date(2026, 11, 16)  # a Monday


@pytest.fixture(autouse=True)
def frozen_today(monkeypatch):
    monkeypatch.setattr(utils, "local_now", lambda: datetime(2026, 11, 16, 9, 0, tzinfo=ZoneInfo("Asia/Seoul")))


def post(client, exercise="Squat", day=None, **numbers):
    body = {"exercise": exercise, **(numbers or {"sets": 3, "reps": 10})}
    if day:
        body["date"] = day
    response = client.post("/api/workouts", json=body)
    assert response.status_code == 201, response.text
    return response.json()


def say(client, text, **body):
    return client.post("/api/workouts/say", json={"text": text, **body})


# ---------------------------------------------------------------- CRUD


def test_create_fills_in_the_catalog_and_today(client):
    workout = post(client, "Squat", sets=3, reps=20, weight_kg=40)
    assert workout["date"] == "2026-11-16"
    assert (workout["exercise_key"], workout["category"], workout["source"]) == ("squat", "strength", "manual")
    assert workout["routine_id"] is None and workout["id"] > 0


def test_an_unknown_exercise_is_other(client):
    workout = post(client, "Handstand", duration_min=5)
    assert (workout["exercise_key"], workout["category"]) == (None, "other")


def test_update_and_delete(client):
    workout = post(client, "Squat", "2026-11-10", sets=3, reps=10)
    changed = client.put(f"/api/workouts/{workout['id']}", json={"exercise": "Plank", "duration_min": 2, "date": "2026-11-11"})
    assert changed.status_code == 200
    assert changed.json()["exercise_key"] == "plank" and changed.json()["date"] == "2026-11-11"
    assert changed.json()["sets"] is None
    assert client.delete(f"/api/workouts/{workout['id']}").status_code == 204
    assert client.get("/api/workouts").json() == []


def test_unknown_id_is_404(client):
    body = {"exercise": "Squat", "reps": 5}
    assert client.put("/api/workouts/99", json=body).status_code == 404
    assert client.delete("/api/workouts/99").status_code == 404


@pytest.mark.parametrize(
    "body",
    [
        {"exercise": "Squat"},  # no number at all
        {"exercise": "Squat", "weight_kg": 40},  # weight alone is not enough
        {"exercise": "", "reps": 5},
        {"exercise": "x" * 41, "reps": 5},
        {"exercise": "Squat", "sets": 0},
        {"exercise": "Squat", "sets": 51},
        {"exercise": "Squat", "reps": 1001},
        {"exercise": "Squat", "reps": 5, "weight_kg": 501},
        {"exercise": "Squat", "reps": 5, "weight_kg": -1},
        {"exercise": "Run", "duration_min": 601},
        {"exercise": "Run", "distance_km": 0.05},
        {"exercise": "Run", "distance_km": 301},
        {"exercise": "Squat", "reps": 5, "note": "n" * 201},
        {"exercise": "Squat", "reps": 5, "category": "dance"},
    ],
)
def test_bounds_are_422(client, body):
    assert client.post("/api/workouts", json=body).status_code == 422


def test_the_edges_are_accepted(client):
    for body in ({"exercise": "a", "sets": 1}, {"exercise": "b", "reps": 1000}, {"exercise": "c", "distance_km": 0.1, "weight_kg": 0}, {"exercise": "d", "duration_min": 600}):
        assert client.post("/api/workouts", json=body).status_code == 201


# ---------------------------------------------------------------- listing


def test_list_filters_by_date_and_orders_newest_first(client):
    old = post(client, "Squat", "2026-09-01")
    a = post(client, "Lunge", "2026-11-10")
    b = post(client, "Plank", "2026-11-10", duration_min=1)
    c = post(client, "Yoga", "2026-11-14", duration_min=20)

    default = client.get("/api/workouts").json()  # the last 30 days: no September
    assert [w["id"] for w in default] == [c["id"], b["id"], a["id"]]

    ranged = client.get("/api/workouts", params={"from": "2026-11-10", "to": "2026-11-10"}).json()
    assert [w["id"] for w in ranged] == [b["id"], a["id"]]  # same day: newest created first

    everything = client.get("/api/workouts", params={"from": "2026-01-01"}).json()
    assert everything[-1]["id"] == old["id"]


# ---------------------------------------------------------------- catalog


@pytest.mark.parametrize("language, name", [("en", "Squat"), ("zh", "深蹲"), ("ko", "스쿼트"), ("fr", "Squat")])
def test_catalog_is_localized(client, language, name):
    body = client.get("/api/workouts/catalog", headers={"Accept-Language": language}).json()
    assert body["categories"] == ["strength", "cardio", "flexibility", "sports", "other"]
    assert len(body["exercises"]) >= 28
    squat = next(e for e in body["exercises"] if e["key"] == "squat")
    assert squat == {"key": "squat", "name": name, "category": "strength", "unit": "reps"}


# ---------------------------------------------------------------- the said line


def test_korean_line(client):
    response = say(client, "오늘 스쿼트 3세트 20회, 러닝 30분", date="2026-11-16")
    assert response.status_code == 201
    squat, run = response.json()["workouts"]
    assert (squat["exercise_key"], squat["sets"], squat["reps"], squat["source"]) == ("squat", 3, 20, "said")
    assert (run["exercise_key"], run["duration_min"], run["category"]) == ("running", 30, "cardio")
    assert response.json()["unread"] == []


def test_english_line_with_times_and_km(client):
    workouts = say(client, "3x12 bench press 60kg and 5km run").json()["workouts"]
    bench, run = workouts
    assert (bench["sets"], bench["reps"], bench["weight_kg"]) == (3, 12, 60)
    assert (run["exercise_key"], run["distance_km"]) == ("running", 5)


def test_chinese_line_and_yesterday(client):
    workouts = say(client, "昨天跑步40分钟，俯卧撑3组15个").json()["workouts"]
    assert [w["date"] for w in workouts] == ["2026-11-15", "2026-11-15"]
    assert (workouts[0]["exercise_key"], workouts[0]["duration_min"]) == ("running", 40)
    assert (workouts[1]["exercise_key"], workouts[1]["sets"], workouts[1]["reps"]) == ("push_up", 3, 15)


def test_korean_yesterday_moves_from_the_given_date(client):
    workouts = say(client, "어제 플랭크 2분", date="2026-11-10").json()["workouts"]
    assert workouts[0]["date"] == "2026-11-09"


def test_hours_a_bare_time_number_and_own_words(client):
    workouts = say(client, "yoga 1 hour, plank 3, 줄넘기 2시간 30분, handstand 5 min").json()["workouts"]
    assert [w["duration_min"] for w in workouts] == [60, 3, 150, 5]
    assert workouts[3]["exercise"] == "handstand" and workouts[3]["category"] == "other"


def test_unreadable_pieces_go_to_unread(client):
    body = say(client, "squat 20 reps, I felt great").json()
    assert len(body["workouts"]) == 1
    assert body["unread"] == ["I felt great"]


def test_a_catalog_name_without_numbers_or_out_of_bounds_is_unread(client):
    body = say(client, "squat, bench press 9999 reps").json()
    assert body["workouts"] == [] and body["unread"] == ["squat", "bench press 9999 reps"]


def test_nothing_read_is_200_and_saves_nothing(client):
    response = say(client, "nothing to see here")
    assert response.status_code == 200
    assert response.json() == {"workouts": [], "unread": ["nothing to see here"]}
    assert client.get("/api/workouts").json() == []


def test_say_bounds(client):
    assert say(client, "").status_code == 422
    assert say(client, "x" * 301).status_code == 422


def test_split_pieces_separators():
    assert service.split_pieces("a, b、c，d; e and f 그리고 g\nh") == list("abcdefgh")


def test_llm_fallback_only_for_a_real_provider(client, monkeypatch):
    from app.llm.mock import MockProvider

    class Scripted:
        name = "scripted"
        calls = 0

        def complete(self, messages):
            Scripted.calls += 1
            return json.dumps({"records": [
                {"piece": 0, "exercise": "kettlebell swing", "sets": 4, "reps": 15, "weight_kg": 16},
                {"piece": 1, "exercise": "bad", "reps": 5000},
            ]})

    # The mock is never asked.
    assert service.read_unread_with_llm(MockProvider(), ["kettlebell swings 4x15"]) == ([], ["kettlebell swings 4x15"])
    records, unread = service.read_unread_with_llm(Scripted(), ["a", "b", "c"])
    assert Scripted.calls == 1  # one call for all the pieces
    assert [r["exercise"] for r in records] == ["kettlebell swing"]
    assert unread == ["b", "c"]  # invalid or unanswered stay unread

    monkeypatch.setattr("app.routers.workouts.get_provider", lambda agent=None: Scripted())
    body = say(client, "foo bar, baz").json()
    assert len(body["workouts"]) == 1 and body["unread"] == ["baz"]


# ---------------------------------------------------------------- summary


def days(client, *dates):
    for d in dates:
        post(client, "Squat", d, sets=1, reps=5)


def test_streak_ending_today(client):
    days(client, "2026-11-14", "2026-11-15", "2026-11-16", "2026-11-10")
    s = client.get("/api/workouts/summary").json()
    assert s["streak"] == 3 and s["best_streak"] == 3


def test_streak_ending_yesterday_counts_and_a_gap_breaks_it(client):
    days(client, "2026-11-13", "2026-11-14", "2026-11-15")
    assert client.get("/api/workouts/summary").json()["streak"] == 3
    days(client, "2026-11-01", "2026-11-02", "2026-11-03", "2026-11-04")
    s = client.get("/api/workouts/summary").json()
    assert (s["streak"], s["best_streak"]) == (3, 4)


def test_no_workout_yesterday_or_today_is_no_streak(client):
    days(client, "2026-11-13")
    assert client.get("/api/workouts/summary").json()["streak"] == 0


def test_by_day_covers_the_whole_window_and_totals(client):
    post(client, "Run", "2026-11-16", duration_min=30)
    post(client, "Yoga", "2026-11-16", duration_min=20)
    post(client, "Squat", "2026-11-12", sets=2, reps=5)
    post(client, "Run", "2026-10-01", duration_min=99)  # outside the 7-day window
    s = client.get("/api/workouts/summary").json()
    assert [d["date"] for d in s["by_day"]] == [f"2026-11-{n:02d}" for n in range(10, 17)]
    assert s["by_day"][-1] == {"date": "2026-11-16", "minutes": 50, "workouts": 2}
    assert s["by_day"][0] == {"date": "2026-11-10", "minutes": 0, "workouts": 0}
    assert (s["days"], s["workouts"], s["total_minutes"]) == (7, 3, 50)
    assert s["by_category"] == {"cardio": 1, "flexibility": 1, "strength": 1}
    assert s["xp"] == 40  # four workouts, all time
    assert len(client.get("/api/workouts/summary", params={"days": 90}).json()["by_day"]) == 90
    assert len(client.get("/api/workouts/summary", params={"days": 30}).json()["by_day"]) == 30


def test_summary_days_must_be_7_30_or_90(client):
    assert client.get("/api/workouts/summary", params={"days": 10}).status_code == 422


# ---------------------------------------------------------------- routines

ROUTINE = {
    "name": "Upper A",
    "weekdays": [4, 0, 0],
    "items": [{"exercise": "Bench press", "sets": 4, "reps": 10, "weight_kg": 50}, {"exercise": "Plank", "duration_min": 2}],
}


def make_routine(client, **changes):
    response = client.post("/api/routines", json={**ROUTINE, **changes})
    assert response.status_code == 201, response.text
    return response.json()


def test_routine_crud(client):
    routine = make_routine(client)
    assert routine["weekdays"] == [0, 4]  # sorted, no duplicates
    assert routine["items"][0]["exercise_key"] == "bench_press" and routine["items"][0]["category"] == "strength"
    assert client.get("/api/routines").json()[0]["id"] == routine["id"]

    changed = client.put(f"/api/routines/{routine['id']}", json={**ROUTINE, "name": "Upper B", "weekdays": [2]})
    assert changed.json()["name"] == "Upper B" and changed.json()["weekdays"] == [2]
    assert client.delete(f"/api/routines/{routine['id']}").status_code == 204
    assert client.get("/api/routines").json() == []
    assert client.put("/api/routines/9", json=ROUTINE).status_code == 404
    assert client.delete("/api/routines/9").status_code == 404


@pytest.mark.parametrize(
    "changes",
    [
        {"name": ""},
        {"name": "n" * 31},
        {"weekdays": []},
        {"weekdays": [7]},
        {"weekdays": [-1]},
        {"items": []},
        {"items": [{"exercise": "Plank", "duration_min": 1}] * 13},
        {"items": [{"exercise": "Plank"}]},
    ],
)
def test_routine_422(client, changes):
    assert client.post("/api/routines", json={**ROUTINE, **changes}).status_code == 422


def test_routines_day_check_and_uncheck(client):
    routine = make_routine(client)
    rid = routine["id"]
    assert client.get("/api/routines/day", params={"date": "2026-11-17"}).json() == []  # a Tuesday

    monday = client.get("/api/routines/day", params={"date": "2026-11-16"}).json()
    assert len(monday) == 1 and monday[0]["done"] is False
    assert [i["workout_id"] for i in monday[0]["items"]] == [None, None]

    checked = client.post(f"/api/routines/{rid}/items/0/check", json={"date": "2026-11-16"})
    assert checked.status_code == 201
    workout = checked.json()
    assert (workout["source"], workout["routine_id"], workout["routine_item"], workout["sets"]) == ("routine", rid, 0, 4)
    assert client.post(f"/api/routines/{rid}/items/0/check", json={"date": "2026-11-16"}).status_code == 409

    monday = client.get("/api/routines/day", params={"date": "2026-11-16"}).json()
    assert monday[0]["items"][0]["workout_id"] == workout["id"] and monday[0]["done"] is False
    # no body at all means today
    assert client.post(f"/api/routines/{rid}/items/1/check").status_code == 201
    assert client.get("/api/routines/day", params={"date": "2026-11-16"}).json()[0]["done"] is True

    assert client.delete(f"/api/routines/{rid}/items/0/check", params={"date": "2026-11-16"}).status_code == 204
    assert client.delete(f"/api/routines/{rid}/items/0/check", params={"date": "2026-11-16"}).status_code == 404
    assert client.get("/api/routines/day", params={"date": "2026-11-16"}).json()[0]["done"] is False
    assert client.post(f"/api/routines/{rid}/items/5/check").status_code == 404
    assert client.post("/api/routines/99/items/0/check").status_code == 404


def test_full_routine_bonus_in_xp_and_history_survives_delete(client):
    rid = make_routine(client)["id"]
    for index in (0, 1):
        client.post(f"/api/routines/{rid}/items/{index}/check", json={"date": "2026-11-16"})
    assert client.get("/api/workouts/summary").json()["xp"] == 2 * 10 + 20
    # half done on another scheduled day: no bonus
    client.post(f"/api/routines/{rid}/items/0/check", json={"date": "2026-11-09"})
    assert client.get("/api/workouts/summary").json()["xp"] == 3 * 10 + 20
    # checked on a day the routine is not scheduled (a Tuesday): no bonus
    for index in (0, 1):
        client.post(f"/api/routines/{rid}/items/{index}/check", json={"date": "2026-11-17"})
    assert client.get("/api/workouts/summary").json()["xp"] == 5 * 10 + 20

    client.delete(f"/api/routines/{rid}")
    kept = client.get("/api/workouts", params={"from": "2026-11-01", "to": "2026-11-30"}).json()
    assert len(kept) == 5 and all(w["routine_id"] == rid for w in kept)


# ---------------------------------------------------------------- export


def seed_export(client):
    post(client, "스쿼트", "2026-11-10", sets=3, reps=20, weight_kg=40, note="좋았다, 쉬웠다")
    post(client, "Run", "2026-11-12", distance_km=5.5, duration_min=30)


def test_export_csv(client):
    seed_export(client)
    response = client.get("/api/workouts/export", params={"format": "csv"})
    assert response.headers["content-type"] == "text/csv; charset=utf-8"
    assert response.headers["content-disposition"] == 'attachment; filename="workouts-20261116.csv"'
    assert response.content.startswith(b"\xef\xbb\xbf")
    lines = response.content.decode("utf-8-sig").splitlines()
    assert lines[0] == "date,exercise,category,sets,reps,weight_kg,duration_min,distance_km,note"
    assert lines[1].startswith("2026-11-10,스쿼트,strength,3,20,40.0,,,")
    assert "좋았다, 쉬웠다" in lines[1]
    assert lines[2].startswith("2026-11-12,Run,cardio,,,,30,5.5,")


def test_export_xlsx(client):
    seed_export(client)
    response = client.get("/api/workouts/export", params={"format": "xlsx"})
    assert response.headers["content-type"].startswith("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    assert response.headers["content-disposition"] == 'attachment; filename="workouts-20261116.xlsx"'
    rows = list(load_workbook(io.BytesIO(response.content)).active.iter_rows(values_only=True))
    assert rows[0] == tuple(service.COLUMNS)
    assert rows[1][:5] == ("2026-11-10", "스쿼트", "strength", 3, 20) and rows[1][8] == "좋았다, 쉬웠다"
    assert rows[2][7] == 5.5


def test_export_format_is_checked(client):
    assert client.get("/api/workouts/export", params={"format": "pdf"}).status_code == 422


def upload(client, name, data):
    return client.post("/api/workouts/import", files={"file": (name, data)})


# ---------------------------------------------------------------- import


def test_csv_round_trip_with_korean(client):
    seed_export(client)
    exported = client.get("/api/workouts/export", params={"format": "csv"}).content
    # importing the export into the same account: everything is a duplicate
    assert upload(client, "w.csv", exported).json() == {"imported": 0, "skipped": 2, "errors": []}
    for w in client.get("/api/workouts").json():
        client.delete(f"/api/workouts/{w['id']}")
    assert upload(client, "w.csv", exported).json() == {"imported": 2, "skipped": 0, "errors": []}
    back = client.get("/api/workouts", params={"from": "2026-11-01"}).json()
    squat = next(w for w in back if w["exercise"] == "스쿼트")
    assert (squat["source"], squat["sets"], squat["weight_kg"], squat["note"]) == ("import", 3, 40, "좋았다, 쉬웠다")
    assert squat["exercise_key"] == "squat"


def test_csv_with_a_duplicate_and_bad_rows(client):
    post(client, "Squat", "2026-11-10", sets=3, reps=10)
    text = "\n".join(
        [
            "date,exercise,category,sets,reps,weight_kg,duration_min,distance_km,note",
            "2026-11-10,Squat,,3,10,,,,",  # already there
            "2026-11-11,Lunge,strength,2,12,,,,",  # fine
            "2026-11-11,Lunge,strength,2,12,,,,",  # same as the row above
            "11/12/2026,Plank,,,,,2,,",  # bad date (row 5)
            "2026-11-12,Plank,dance,,,,2,,",  # bad category
            "2026-11-12,Plank,,,,,,,",  # no numbers
            "2026-11-12,Plank,,x,,,,,",  # not a number
            "2026-11-12,Plank,,,,,2,,",  # fine, no category: from the catalog
            "",
        ]
    )
    result = upload(client, "w.csv", text.encode("utf-8")).json()
    assert (result["imported"], result["skipped"]) == (2, 2)
    assert [e["row"] for e in result["errors"]] == [5, 6, 7, 8]
    assert "date" in result["errors"][0]["reason"]
    plank = next(w for w in client.get("/api/workouts").json() if w["exercise"] == "Plank")
    assert plank["category"] == "strength"


def test_import_xlsx(client):
    book = Workbook()
    sheet = book.active
    sheet.append(service.COLUMNS)
    sheet.append([date(2026, 11, 3), "Yoga", None, None, None, None, 45.0, None, "morning"])
    sheet.append(["2026-11-04", "Yoga", "flexibility", None, None, None, 45, None, None])
    sheet.append(["2026-11-04", "Yoga", "flexibility", None, None, None, 45, None, None])  # duplicate
    sheet.append(["nonsense", "Yoga", None, None, None, None, 45, None, None])
    out = io.BytesIO()
    book.save(out)
    result = upload(client, "w.xlsx", out.getvalue()).json()
    assert (result["imported"], result["skipped"]) == (2, 1)
    assert result["errors"][0]["row"] == 5
    first = client.get("/api/workouts", params={"from": "2026-11-03", "to": "2026-11-03"}).json()[0]
    assert (first["duration_min"], first["category"], first["note"]) == (45, "flexibility", "morning")


def test_import_rejects_unreadable_files(client):
    assert upload(client, "w.csv", b"foo,bar\n1,2\n").status_code == 400  # no date / exercise header
    assert upload(client, "w.csv", b"").status_code == 400
    assert upload(client, "w.xlsx", b"PK not really").status_code == 400
    assert upload(client, "w.csv", b"x" * (service.MAX_IMPORT_BYTES + 1)).status_code == 413


def test_life_summary_counts_workout_days_as_exercise_days(client):
    """A logged workout makes that day an exercise day on the Life page (#39), like a check-in."""
    from app.utils import local_today

    today = local_today().isoformat()
    client.post("/api/workouts", json={"date": today, "exercise": "Squat", "sets": 3, "reps": 10})
    summary = client.get("/api/life", params={"days": 7}).json()["summary"]
    assert summary["exercise_days"] == 1
