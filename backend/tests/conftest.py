import os
import socket

# 测试绝不能碰真实的数据库文件。app.db 在 import 时就会按 DATABASE_URL 建引擎（建了也不连），
# 所以必须在 import app 之前设好；每个用到数据库的测试再把 app.db.engine 换成自己的内存引擎。
os.environ["DATABASE_URL"] = "sqlite://"

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlmodel import Session, SQLModel, create_engine  # noqa: E402
from sqlmodel.pool import StaticPool  # noqa: E402

import app.db as app_db  # noqa: E402
from app.config import settings  # noqa: E402
from app.db import get_session  # noqa: E402
from app.main import app  # noqa: E402


@pytest.fixture(autouse=True)
def _force_mock_provider():
    # The default (unpatched) provider must always be MockProvider in tests,
    # regardless of what's configured in a local backend/.env — otherwise
    # whichever real key happens to be present silently swaps every test
    # that relies on get_provider()'s default onto a real network call.
    #
    # It has its own MonkeyPatch rather than the test's `monkeypatch`: a test calling
    # monkeypatch.undo() must not be able to undo this.
    with pytest.MonkeyPatch.context() as mp:
        for field in ("gemini_api_key", "deepseek_api_key", "openai_api_key", "kimi_api_key"):
            mp.setattr(settings, field, "")
        # 显式指定也要清掉，否则本地 .env 里的 LLM_PROVIDER 会绕过上面这几行。
        mp.setattr(settings, "llm_provider", "")
        mp.setattr(settings, "llm_model", "")
        mp.setattr(settings, "llm_model_overrides", "")
        # 搜索是独立的一层，同理不能让本地 key 把测试悄悄切到真实网络。
        mp.setattr(settings, "tavily_api_key", "")
        yield


_LOOPBACK = {"127.0.0.1", "::1", "localhost"}


@pytest.fixture(autouse=True)
def _block_the_network():
    """No test may reach a real LLM or search API, whatever the local .env holds.

    The Mock provider is what makes tests offline; this is the backstop for the day a test
    lets a real provider through anyway: it fails loudly instead of quietly spending money.
    Loopback stays open. (Own MonkeyPatch, like the fixture above, so monkeypatch.undo() in
    a test cannot lift it.)
    """

    def host_of(address) -> str:
        return address[0] if isinstance(address, tuple) else str(address)

    real_connect = socket.socket.connect
    real_getaddrinfo = socket.getaddrinfo

    def guarded_connect(self, address, *args, **kwargs):
        if self.family != socket.AF_UNIX and host_of(address) not in _LOOPBACK:
            raise AssertionError(f"a test tried to reach the network: {address!r}")
        return real_connect(self, address, *args, **kwargs)

    def guarded_getaddrinfo(host, *args, **kwargs):
        if host is not None and host not in _LOOPBACK:
            raise AssertionError(f"a test tried to resolve a real host: {host!r}")
        return real_getaddrinfo(host, *args, **kwargs)

    with pytest.MonkeyPatch.context() as mp:
        mp.setattr(socket.socket, "connect", guarded_connect)
        mp.setattr(socket, "getaddrinfo", guarded_getaddrinfo)
        yield


@pytest.fixture(name="client_engine")
def client_engine_fixture(monkeypatch):
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    SQLModel.metadata.create_all(engine)
    # lifespan 的 init_db()、请求用的 get_session、后台任务都读 app.db.engine，换掉它就一起换。
    monkeypatch.setattr(app_db, "engine", engine)
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
