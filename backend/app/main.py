import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.db import init_db
from app.llm import get_provider
from app.routers import audits, chat, checkins, courses, goals, graph, journal, narrator, plan, principles, profile, skills, uploads

logging.basicConfig(level=logging.INFO)


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield


app = FastAPI(title="Self-Infinity API", lifespan=lifespan)

# Flutter 的 web 开发服务器每次起在不同的端口，所以放行任意 localhost / 127.0.0.1 端口。
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"^http://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(skills.router)
app.include_router(courses.router)
app.include_router(audits.router)
app.include_router(principles.router)
app.include_router(graph.router)
app.include_router(checkins.router)
app.include_router(narrator.router)
app.include_router(plan.router)
app.include_router(chat.router)
app.include_router(uploads.router)
app.include_router(profile.router)
app.include_router(journal.router)
app.include_router(goals.router)


@app.get("/api/health")
def health():
    return {"status": "ok", "llm_provider": get_provider().name}


# Dev workflow (run.sh) runs `flutter run` on :8090 separately, so this mount is
# only used by Self-Infinity.command, which builds the Flutter web app once into
# app/build/web and lets this process serve it — one port, one thing to start.
# Registered last: Starlette matches routes in registration order, so the
# `/api/...` routers above still take priority over this catch-all mount.
_WEB_BUILD = Path(__file__).resolve().parent.parent.parent / "app" / "build" / "web"
if _WEB_BUILD.is_dir():
    app.mount("/", StaticFiles(directory=_WEB_BUILD, html=True), name="app")
