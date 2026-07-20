import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.db import get_session, init_db
from app.llm import get_provider
from app.routers import audits, checkins, focus, graph, principles, skills
from app.seed import seed_skill_tree

logging.basicConfig(level=logging.INFO)


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    session = next(get_session())
    seed_skill_tree(session)
    yield


app = FastAPI(title="Self-Infinity API", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(skills.router)
app.include_router(audits.router)
app.include_router(principles.router)
app.include_router(checkins.router)
app.include_router(focus.router)
app.include_router(graph.router)


@app.get("/api/health")
def health():
    return {"status": "ok", "llm_provider": get_provider().name}


# Dev workflow (run.sh) serves the frontend separately via `vite dev` on
# :5173 with a proxy back to this app, so `frontend/dist` won't exist and
# this mount is skipped. For personal daily use (Self-Infinity.command),
# the frontend is built once and served by this same process — one port,
# one thing to start, no separate dev server. Registered last: Starlette
# matches routes in registration order, so the `/api/...` routers above
# still take priority over this catch-all static mount.
_FRONTEND_DIST = Path(__file__).resolve().parent.parent.parent / "frontend" / "dist"
if _FRONTEND_DIST.is_dir():
    app.mount("/", StaticFiles(directory=_FRONTEND_DIST, html=True), name="frontend")
