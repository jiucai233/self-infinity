"""The realtime Guide's tools and spoken lines (contract #36): POST /api/chat/act and /api/chat/log."""


def test_a_check_in_from_the_guide_saves_their_words_and_the_receipt(client):
    response = client.post("/api/chat/act", json={"intent": "checkin", "said": "I slept 7 hours and went for a run"})
    assert response.status_code == 200
    messages = response.json()["messages"]
    assert [m["role"] for m in messages] == ["user", "assistant"]
    assert messages[0]["content"] == "I slept 7 hours and went for a run"
    assert messages[1]["action"]["type"] == "checkin"
    assert client.get("/api/checkins/today").json()["sleep_hours"] == 7


def test_the_check_in_falls_back_to_the_words_the_model_passed(client):
    messages = client.post("/api/chat/act", json={"intent": "checkin", "args": {"said": "slept 6 hours"}}).json()["messages"]
    assert [m["role"] for m in messages] == ["assistant"]
    assert client.get("/api/checkins/today").json()["sleep_hours"] == 6


def test_opening_a_node_or_the_map_navigates(client):
    client.post("/api/skills/generate", json={"topic": "math"})
    node = client.post("/api/chat/act", json={"intent": "open_skill", "args": {"skill": "discriminant"}}).json()["messages"][-1]
    assert node["action"]["type"] == "navigate"
    assert node["action"]["scene"] == "skill"
    assert node["agent"] == "front_desk"
    unknown = client.post("/api/chat/act", json={"intent": "open_skill", "args": {"skill": "astrophysics"}}).json()
    assert unknown["messages"][-1]["action"] is None
    map_ = client.post("/api/chat/act", json={"intent": "open_map"}).json()["messages"][-1]
    assert map_["action"] == {"type": "navigate", "scene": "map"}


def test_building_a_course_from_the_guide(client):
    messages = client.post("/api/chat/act", json={"intent": "generate_course", "args": {"topic": "math"}, "said": "teach me math"}).json()["messages"]
    assert messages[-1]["action"]["type"] == "course"
    assert len(client.get("/api/courses").json()) == 1


def test_bad_tool_calls_are_400s(client):
    assert client.post("/api/chat/act", json={"intent": "generate_course", "args": {}}).status_code == 400
    assert client.post("/api/chat/act", json={"intent": "checkin"}).status_code == 400
    assert client.post("/api/chat/act", json={"intent": "none"}).status_code == 422


def test_spoken_lines_are_kept_in_the_history(client):
    response = client.post(
        "/api/chat/log",
        json={"messages": [
            {"role": "user", "content": "Hi there"},
            {"role": "assistant", "content": "  Hi! What shall we learn today?  "},
            {"role": "user", "content": "   "},
        ]},
    )
    saved = response.json()["messages"]
    assert [(m["role"], m["content"], m["agent"]) for m in saved] == [
        ("user", "Hi there", None),
        ("assistant", "Hi! What shall we learn today?", "front_desk"),
    ]
    history = client.get("/api/chat/history").json()
    assert [m["content"] for m in history] == ["Hi there", "Hi! What shall we learn today?"]
    assert client.post("/api/chat/log", json={"messages": [{"role": "system", "content": "x"}]}).status_code == 422
