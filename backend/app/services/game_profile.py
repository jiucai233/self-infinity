"""The player's rules of the game (contract section 6, endpoints 25-26). No LLM.

Not to be confused with services/profile.py, which builds ProfileFacts from the learning history.
"""

import json
from datetime import datetime

from sqlmodel import Session

from app.models import Profile, utcnow
from app.schemas import ProfileOut, ProfileUpdate

PROFILE_ID = 1  # a single row


def _out(row: Profile | None) -> ProfileOut:
    if row is None:
        return ProfileOut(identity="", vision="", anti_vision="", rules=[], updated_at=None, onboarded=False)
    return ProfileOut(
        identity=row.identity,
        vision=row.vision,
        anti_vision=row.anti_vision,
        rules=json.loads(row.rules_json),
        updated_at=row.updated_at,
        onboarded=row.onboarded_at is not None,
    )


def get_profile(session: Session) -> ProfileOut:
    return _out(session.get(Profile, PROFILE_ID))


def update_profile(session: Session, update: ProfileUpdate, now: datetime | None = None) -> ProfileOut:
    row = session.get(Profile, PROFILE_ID) or Profile(id=PROFILE_ID)
    for name in update.model_fields_set:
        if name == "rules":
            row.rules_json = json.dumps(update.rules, ensure_ascii=False)
        elif name == "onboarded":
            row.onboarded_at = (now or utcnow()) if update.onboarded else None
        else:
            setattr(row, name, getattr(update, name))
    row.updated_at = now or utcnow()
    session.add(row)
    session.commit()
    session.refresh(row)
    return _out(row)
