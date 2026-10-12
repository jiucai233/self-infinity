"""What the LLM layer knows about the request it runs in: the account's database, where every
call is logged (LLMCall), the audit the calls belong to, and the provider the account chose.

One RequestContext per HTTP request, held in a context variable. The variable is set in a plain
ASGI middleware (app/main.py), not in get_session: sync dependencies and endpoints run in a
threadpool with a copy of the context, so a `.set()` there would not reach the endpoint. They all
see the same object, though, so get_session only fills it in (`ctx.bind = bind`), and the
request's background tasks still have it.

Without a context (scripts, tests that call a service directly) nothing is logged and the
server's provider is used.
"""

import logging
from contextvars import ContextVar, Token

from sqlmodel import Session

from app.models import LLMCall, Profile

logger = logging.getLogger(__name__)

PROFILE_ID = 1  # the single Profile row (app/services/game_profile.py)


class RequestContext:
    def __init__(self) -> None:
        # The account's engine (its schema); None until get_session ran.
        self.bind = None
        # The audit this request answers, if any.
        self.audit_id: int | None = None
        # Profile.llm_provider, read once per request; None = not read yet, "" = no choice.
        self.choice: str | None = None


_context: ContextVar[RequestContext | None] = ContextVar("llm_request", default=None)


def begin() -> Token:
    """A fresh context for one request; the middleware passes the token to end()."""
    return _context.set(RequestContext())


def end(token: Token) -> None:
    _context.reset(token)


def current() -> RequestContext | None:
    return _context.get()


def account_choice() -> str:
    """The provider this request's account chose, "" for none or outside a request."""
    ctx = current()
    if ctx is None or ctx.bind is None:
        return ""
    if ctx.choice is None:
        try:
            with Session(ctx.bind) as session:
                row = session.get(Profile, PROFILE_ID)
            ctx.choice = (row.llm_provider or "") if row else ""
        except Exception:
            logger.warning("could not read the account's LLM provider", exc_info=True)
            ctx.choice = ""
    return ctx.choice


def record(
    *,
    provider: str,
    model: str,
    agent: str,
    input_tokens: int = 0,
    cached_tokens: int = 0,
    output_tokens: int = 0,
    elapsed_ms: float = 0,
    ok: bool = True,
) -> None:
    """Logs one call in the request's account. Its own short session, so the row is kept
    whatever the request's transaction does. Never raises."""
    ctx = current()
    if ctx is None or ctx.bind is None:
        return
    try:
        with Session(ctx.bind) as session:
            session.add(
                LLMCall(
                    agent=agent or "-",
                    provider=provider,
                    model=model,
                    input_tokens=_count(input_tokens),
                    cached_tokens=_count(cached_tokens),
                    output_tokens=_count(output_tokens),
                    elapsed_ms=round(elapsed_ms),
                    ok=ok,
                    audit_id=ctx.audit_id,
                )
            )
            session.commit()
    except Exception:
        logger.warning("could not log an LLM call (agent=%s provider=%s)", agent, provider, exc_info=True)


def _count(value) -> int:
    """A token count from a provider's usage block; 0 for anything missing or odd."""
    try:
        return max(int(value or 0), 0)
    except (TypeError, ValueError):
        return 0
