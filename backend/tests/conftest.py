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
    for field in ("gemini_api_key", "deepseek_api_key", "openai_api_key", "kimi_api_key"):
        monkeypatch.setattr(settings, field, "")
    # 显式指定也要清掉，否则本地 .env 里的 LLM_PROVIDER 会绕过上面这几行。
    monkeypatch.setattr(settings, "llm_provider", "")
    # 搜索是独立的一层，同理不能让本地 key 把测试悄悄切到真实网络。
    monkeypatch.setattr(settings, "tavily_api_key", "")


@pytest.fixture(name="client_engine")
def client_engine_fixture():
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    SQLModel.metadata.create_all(engine)
    with Session(engine) as session:
        seed_skill_tree(session)
    return engine


@pytest.fixture(name="client")
def client_fixture(client_engine):
    def get_session_override():
        with Session(client_engine) as session:
            yield session

    app.dependency_overrides[get_session] = get_session_override
    with TestClient(app) as client:
        yield client
    app.dependency_overrides.clear()
