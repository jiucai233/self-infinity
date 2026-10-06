"""Who is calling (contract section 7).

`AUTH_MODE=dev` (the default): nobody signs in; every request is the local user, whose data lives
in the database's default schema — exactly how the app worked before accounts existed.

`AUTH_MODE=supabase`: every request carries the Supabase access token of a signed-in user
(`Authorization: Bearer <jwt>`). The token is verified here — with the project's JWKS
(asymmetric keys, the Supabase default) or, for older projects, the HS256 JWT secret — and the
user's data lives in a schema of its own, `u_<user id without dashes>` (see app/db.py).
"""

import uuid
from dataclasses import dataclass
from functools import lru_cache

import jwt
from fastapi import Header, HTTPException

from app.config import settings

AUDIENCE = "authenticated"


@dataclass(frozen=True)
class CurrentUser:
    id: str
    email: str | None = None

    @property
    def schema(self) -> str | None:
        """The database schema of this user; None = the default schema (dev mode)."""
        if self.id == DEV_USER.id:
            return None
        return "u_" + uuid.UUID(self.id).hex


DEV_USER = CurrentUser(id="dev")


@lru_cache(maxsize=4)
def _jwks_client(url: str) -> jwt.PyJWKClient:
    return jwt.PyJWKClient(f"{url.rstrip('/')}/auth/v1/.well-known/jwks.json", cache_keys=True)


def verify_token(token: str) -> dict:
    """The verified claims of a Supabase access token; raises jwt.PyJWTError otherwise."""
    alg = jwt.get_unverified_header(token).get("alg")
    if alg == "HS256":
        if not settings.supabase_jwt_secret:
            raise jwt.InvalidTokenError("HS256 token but SUPABASE_JWT_SECRET is not set")
        return jwt.decode(token, settings.supabase_jwt_secret, algorithms=["HS256"], audience=AUDIENCE)
    if not settings.supabase_url:
        raise jwt.InvalidTokenError("SUPABASE_URL is not set")
    key = _jwks_client(settings.supabase_url).get_signing_key_from_jwt(token).key
    return jwt.decode(token, key, algorithms=["ES256", "RS256"], audience=AUDIENCE)


def current_user(authorization: str | None = Header(default=None)) -> CurrentUser:
    if settings.auth_mode != "supabase":
        return DEV_USER
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(401, "not signed in")
    try:
        claims = verify_token(authorization[7:].strip())
        user_id = str(uuid.UUID(str(claims.get("sub"))))
    except (jwt.PyJWTError, ValueError):
        raise HTTPException(401, "session expired or invalid") from None
    return CurrentUser(id=user_id, email=claims.get("email"))
