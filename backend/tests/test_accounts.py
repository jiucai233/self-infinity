"""Accounts (contract section 7): Supabase tokens, one schema per account, the onboarding flag."""

import time
import uuid

import jwt
import pytest
from fastapi.testclient import TestClient

import app.db as app_db
from app.auth import CurrentUser
from app.config import settings
from app.main import app

SECRET = "test-secret-at-least-32-bytes-long!!"
ALICE = str(uuid.uuid4())
BOB = str(uuid.uuid4())


def token(sub: str, *, secret: str = SECRET, aud: str = "authenticated", exp_in: int = 3600, email=None) -> str:
    claims = {"sub": sub, "aud": aud, "exp": int(time.time()) + exp_in, "role": "authenticated"}
    if email:
        claims["email"] = email
    return jwt.encode(claims, secret, algorithm="HS256")


def auth(sub: str, **kw) -> dict:
    return {"Authorization": f"Bearer {token(sub, **kw)}"}


@pytest.fixture(name="accounts")
def accounts_fixture(client_engine, monkeypatch):
    """The real get_session (no override) with AUTH_MODE=supabase and an HS256 secret."""
    monkeypatch.setattr(settings, "auth_mode", "supabase")
    monkeypatch.setattr(settings, "supabase_jwt_secret", SECRET)
    monkeypatch.setattr(app_db, "_ready", set())
    with TestClient(app) as client:
        yield client


def test_dev_mode_needs_no_token(client):
    response = client.get("/api/me")
    assert response.json() == {"id": "dev", "email": None, "auth_mode": "dev", "is_dev": True}


def test_without_a_valid_token_every_endpoint_is_401(accounts):
    assert accounts.get("/api/courses").status_code == 401
    assert accounts.get("/api/courses", headers={"Authorization": "Bearer nonsense"}).status_code == 401
    assert accounts.get("/api/courses", headers=auth(ALICE, secret="x" * 40)).status_code == 401
    assert accounts.get("/api/courses", headers=auth(ALICE, aud="anon")).status_code == 401
    assert accounts.get("/api/courses", headers=auth(ALICE, exp_in=-10)).status_code == 401
    assert accounts.get("/api/courses", headers=auth("not-a-uuid")).status_code == 401
    # Health stays open (it is what the platform pings).
    assert accounts.get("/api/health").status_code == 200


def test_me_names_the_signed_in_account(accounts):
    response = accounts.get("/api/me", headers=auth(ALICE, email="alice@example.com"))
    assert response.json() == {"id": ALICE, "email": "alice@example.com", "auth_mode": "supabase", "is_dev": False}


def test_each_account_sees_only_its_own_data(accounts):
    a, b = auth(ALICE), auth(BOB)
    course = accounts.post("/api/skills/generate", json={"topic": "math"}, headers=a)
    assert course.status_code == 200
    accounts.put("/api/profile", json={"identity": "I am Alice"}, headers=a)
    accounts.post("/api/goals", json={"title": "Alice's quest"}, headers=a)
    accounts.post("/api/chat", json={"message": "I slept 7 hours"}, headers=a)

    assert len(accounts.get("/api/courses", headers=a).json()) == 1
    assert accounts.get("/api/courses", headers=b).json() == []
    assert accounts.get("/api/skills", headers=b).json() == []
    assert accounts.get("/api/goals", headers=b).json() == []
    assert accounts.get("/api/chat/history", headers=b).json() == []
    assert accounts.get("/api/profile", headers=b).json()["identity"] == ""
    assert accounts.get("/api/profile", headers=a).json()["identity"] == "I am Alice"
    # Ids are per account: Bob's node 1 does not exist, Alice's does.
    assert accounts.get("/api/skills/1/overview", headers=b).status_code == 404
    assert accounts.get("/api/skills/1/overview", headers=a).status_code == 200

    # Bob's first course also starts at id 1, in his own schema.
    assert accounts.post("/api/skills/generate", json={"topic": "Writing"}, headers=b).json()["course"]["id"] == 1
    assert [c["topic"] for c in accounts.get("/api/courses", headers=a).json()] == ["math"]


def test_schema_names_come_from_the_user_id():
    user = CurrentUser(id="3f2a9a8e-1c2b-4d5e-8f90-1234567890ab")
    assert user.schema == "u_3f2a9a8e1c2b4d5e8f901234567890ab"
    assert CurrentUser(id="dev").schema is None


def test_onboarding_flag(accounts):
    a = auth(ALICE)
    assert accounts.get("/api/profile", headers=a).json()["onboarded"] is False
    done = accounts.put("/api/profile", json={"onboarded": True}, headers=a).json()
    assert done["onboarded"] is True
    assert accounts.get("/api/profile", headers=auth(BOB)).json()["onboarded"] is False
    # Other fields are kept; false shows the tutorial again.
    accounts.put("/api/profile", json={"identity": "x"}, headers=a)
    assert accounts.get("/api/profile", headers=a).json()["onboarded"] is True
    assert accounts.put("/api/profile", json={"onboarded": False}, headers=a).json()["onboarded"] is False
    assert accounts.put("/api/profile", json={"onboarded": None}, headers=a).status_code == 422
