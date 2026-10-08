"""GET/PUT /api/profile (contract #25, #26) and GET /api/me (#32). No LLM."""

from fastapi import APIRouter, Depends
from sqlmodel import Session

from app.auth import CurrentUser, current_user
from app.config import settings
from app.db import get_session
from app.routers.dev import is_dev
from app.schemas import MeOut, ProfileOut, ProfileUpdate
from app.services import game_profile

router = APIRouter(prefix="/api", tags=["profile"])


@router.get("/profile", response_model=ProfileOut)
def get_profile(session: Session = Depends(get_session)):
    return game_profile.get_profile(session)


@router.put("/profile", response_model=ProfileOut)
def put_profile(body: ProfileUpdate, session: Session = Depends(get_session)):
    return game_profile.update_profile(session, body)


@router.get("/me", response_model=MeOut)
def get_me(user: CurrentUser = Depends(current_user)):
    return MeOut(id=user.id, email=user.email, auth_mode=settings.auth_mode, is_dev=is_dev(user))
