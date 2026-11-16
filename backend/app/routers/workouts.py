"""Workouts (contract #54a-i) and routines (#54j-p). Thin: the logic is in app/services/workouts.py."""

import json
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query, Response, UploadFile
from sqlmodel import Session, select

from app import utils
from app.db import get_session
from app.llm import get_provider
from app.models import Routine, Workout
from app.schemas import (
    RoutineCheckIn,
    RoutineDayOut,
    RoutineIn,
    RoutineOut,
    WorkoutCatalogOut,
    WorkoutImportOut,
    WorkoutIn,
    WorkoutOut,
    WorkoutSayIn,
    WorkoutSayOut,
    WorkoutSummaryOut,
)
from app.services import workouts as service

router = APIRouter(prefix="/api", tags=["workouts"])

XLSX_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"


def _workout_or_404(session: Session, workout_id: int) -> Workout:
    workout = session.get(Workout, workout_id)
    if workout is None:
        raise HTTPException(404, "Workout not found")
    return workout


def _routine_or_404(session: Session, routine_id: int) -> Routine:
    routine = session.get(Routine, routine_id)
    if routine is None:
        raise HTTPException(404, "Routine not found")
    return routine


@router.get("/workouts/catalog", response_model=WorkoutCatalogOut)
def get_catalog():
    return service.catalog_listing()


@router.get("/workouts", response_model=list[WorkoutOut])
def list_workouts(
    from_: date | None = Query(None, alias="from"), to: date | None = None, session: Session = Depends(get_session)
):
    return service.list_workouts(session, from_, to)


@router.post("/workouts", response_model=WorkoutOut, status_code=201)
def create_workout(body: WorkoutIn, session: Session = Depends(get_session)):
    return service.add_workout(session, body.date or utils.local_today(), body.model_dump())


@router.post("/workouts/say", response_model=WorkoutSayOut, status_code=201)
def say(body: WorkoutSayIn, response: Response, session: Session = Depends(get_session)):
    # The provider is only asked for pieces the rules could not read, and never when it is the mock.
    saved, unread = service.say(session, body.text, body.date, get_provider("workout_reader"))
    if not saved:
        response.status_code = 200
    return {"workouts": saved, "unread": unread}


@router.get("/workouts/summary", response_model=WorkoutSummaryOut)
def get_summary(days: int = Query(7), session: Session = Depends(get_session)):
    if days not in (7, 30, 90):
        raise HTTPException(422, "days must be 7, 30 or 90")
    return service.summary(session, days)


@router.get("/workouts/export")
def export(format: str = Query("csv", pattern="^(csv|xlsx)$"), session: Session = Depends(get_session)):
    stamp = utils.local_today().strftime("%Y%m%d")
    if format == "csv":
        body, media = service.export_csv(session), "text/csv; charset=utf-8"
    else:
        body, media = service.export_xlsx(session), XLSX_TYPE
    return Response(body, media_type=media, headers={"Content-Disposition": f'attachment; filename="workouts-{stamp}.{format}"'})


@router.post("/workouts/import", response_model=WorkoutImportOut)
def import_workouts(file: UploadFile, session: Session = Depends(get_session)):
    # One byte past the limit is enough to tell the file is too big.
    data = file.file.read(service.MAX_IMPORT_BYTES + 1)
    if len(data) > service.MAX_IMPORT_BYTES:
        raise HTTPException(413, "The file is larger than 2 MB")
    try:
        return service.import_file(session, data)
    except ValueError as exc:
        raise HTTPException(400, str(exc))


@router.put("/workouts/{workout_id}", response_model=WorkoutOut)
def update_workout(workout_id: int, body: WorkoutIn, session: Session = Depends(get_session)):
    workout = _workout_or_404(session, workout_id)
    return service.update_workout(workout, session, body.date, body.model_dump())


@router.delete("/workouts/{workout_id}", status_code=204)
def delete_workout(workout_id: int, session: Session = Depends(get_session)):
    session.delete(_workout_or_404(session, workout_id))
    session.commit()


# ---------------------------------------------------------------- routines


@router.get("/routines", response_model=list[RoutineOut])
def list_routines(session: Session = Depends(get_session)):
    return [service.routine_view(r) for r in session.exec(select(Routine).order_by(Routine.id)).all()]


@router.post("/routines", response_model=RoutineOut, status_code=201)
def create_routine(body: RoutineIn, session: Session = Depends(get_session)):
    items = [item.model_dump() for item in body.items]
    return service.routine_view(service.save_routine(session, None, body.name, body.weekdays, items))


@router.get("/routines/day", response_model=list[RoutineDayOut])
def routines_on_day(date: date, session: Session = Depends(get_session)):
    return service.routines_on(session, date)


@router.put("/routines/{routine_id}", response_model=RoutineOut)
def update_routine(routine_id: int, body: RoutineIn, session: Session = Depends(get_session)):
    routine = _routine_or_404(session, routine_id)
    items = [item.model_dump() for item in body.items]
    return service.routine_view(service.save_routine(session, routine, body.name, body.weekdays, items))


@router.delete("/routines/{routine_id}", status_code=204)
def delete_routine(routine_id: int, session: Session = Depends(get_session)):
    # Past check-offs stay as workouts; their routine_id is kept as history.
    session.delete(_routine_or_404(session, routine_id))
    session.commit()


def _item_index_or_404(routine: Routine, index: int) -> None:
    if not 0 <= index < len(json.loads(routine.items_json)):
        raise HTTPException(404, "Routine item not found")


@router.post("/routines/{routine_id}/items/{index}/check", response_model=WorkoutOut, status_code=201)
def check_item(routine_id: int, index: int, body: RoutineCheckIn | None = None, session: Session = Depends(get_session)):
    routine = _routine_or_404(session, routine_id)
    _item_index_or_404(routine, index)
    day = (body.date if body else None) or utils.local_today()
    if service.find_check(session, routine_id, index, day):
        raise HTTPException(409, "Already checked off that day")
    return service.check_item(session, routine, index, day)


@router.delete("/routines/{routine_id}/items/{index}/check", status_code=204)
def uncheck_item(routine_id: int, index: int, date: date, session: Session = Depends(get_session)):
    workout = service.find_check(session, routine_id, index, date)
    if workout is None:
        raise HTTPException(404, "Not checked off that day")
    session.delete(workout)
    session.commit()
