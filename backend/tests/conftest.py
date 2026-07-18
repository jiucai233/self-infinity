import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session, SQLModel, create_engine
from sqlmodel.pool import StaticPool

from app.config import settings
from app.db import get_session
from app.main import app
from app.seed import seed_skill_tree


@pytest.fixture(autouse=True)
def _force_mock_provider(monkeypatch):
    # The default (unpatched) provider must always be MockProvider in tests,
    # regardless of what's configured in a local backend/.env — otherwise
    # whichever real key happens to be present silently swaps every test
    # that relies on get_provider()'s default onto a real network call.
    monkeypatch.setattr(settings, "gemini_api_key", "")
    monkeypatch.setattr(settings, "deepseek_api_key", "")


@pytest.fixture(name="client")
def client_fixture():
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    SQLModel.metadata.create_all(engine)

    def get_session_override():
        with Session(engine) as session:
            yield session

    with Session(engine) as session:
        seed_skill_tree(session)

    app.dependency_overrides[get_session] = get_session_override
    with TestClient(app) as client:
        yield client
    app.dependency_overrides.clear()
