import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.db import get_session, init_db
from app.llm import get_provider
from app.routers import audits, checkins, focus, principles, skills
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


@app.get("/api/health")
def health():
    return {"status": "ok", "llm_provider": get_provider().name}
