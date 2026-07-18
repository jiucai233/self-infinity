from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.db import get_session, init_db
from app.llm import get_provider
from app.routers import audits, principles, skills
from app.seed import seed_skill_tree


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


@app.get("/api/health")
def health():
    return {"status": "ok", "llm_provider": get_provider().name}
