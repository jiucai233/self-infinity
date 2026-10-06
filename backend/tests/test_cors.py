"""CORS：任何 http://localhost:* 和 http://127.0.0.1:* 源都放行（Flutter 的 web 开发服务器端口不固定）。"""

import pytest


def preflight(client, origin: str):
    return client.options(
        "/api/courses",
        headers={"Origin": origin, "Access-Control-Request-Method": "POST", "Access-Control-Request-Headers": "content-type"},
    )


@pytest.mark.parametrize(
    "origin",
    [
        "http://localhost:5173",
        "http://localhost:8090",
        "http://localhost:51234",
        "http://127.0.0.1:8090",
        "http://127.0.0.1:3000",
        "http://localhost",
    ],
)
def test_local_origins_are_allowed(client, origin):
    response = preflight(client, origin)

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == origin


@pytest.mark.parametrize(
    "origin",
    [
        "https://localhost:8090",  # not http
        "http://localhost.evil.example",
        "http://evil.example:8090",
        "http://localhost:80@evil.example",
        "http://192.168.0.2:8090",
    ],
)
def test_other_origins_are_not(client, origin):
    response = preflight(client, origin)

    assert "access-control-allow-origin" not in response.headers


def test_a_normal_request_from_an_allowed_origin_carries_the_header(client):
    response = client.get("/api/courses", headers={"Origin": "http://localhost:62000"})

    assert response.headers["access-control-allow-origin"] == "http://localhost:62000"
