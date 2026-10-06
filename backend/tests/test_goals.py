"""Main quests (contract section 6, endpoints 28-31)."""

from tests.helpers import generate


def test_no_goals_on_a_fresh_database(client):
    assert client.get("/api/goals").json() == []


def test_create_trims_the_title_and_starts_empty(client):
    response = client.post("/api/goals", json={"title": "  Teach calculus to a stranger  "})

    assert response.status_code == 200
    body = response.json()
    assert body["title"] == "Teach calculus to a stranger"
    assert body["course_ids"] == []
    assert client.get("/api/goals").json() == [body]


def test_blank_or_long_titles_are_422(client):
    assert client.post("/api/goals", json={"title": "   "}).status_code == 422
    assert client.post("/api/goals", json={"title": "x" * 81}).status_code == 422
    assert client.post("/api/goals", json={"title": "x" * 80}).status_code == 200


def test_at_most_three_goals(client):
    for i in range(3):
        assert client.post("/api/goals", json={"title": f"Goal {i}"}).status_code == 200

    response = client.post("/api/goals", json={"title": "One too many"})

    assert response.status_code == 409
    assert response.json()["detail"] == "at most 3 main quests"


def test_goals_are_listed_oldest_first(client):
    ids = [client.post("/api/goals", json={"title": t}).json()["id"] for t in ("A", "B", "C")]

    assert [g["id"] for g in client.get("/api/goals").json()] == ids


def test_attach_courses_and_rename(client):
    course = generate(client)["course"]["id"]
    goal = client.post("/api/goals", json={"title": "Old"}).json()["id"]

    response = client.put(f"/api/goals/{goal}", json={"title": "New", "course_ids": [course, course]})

    assert response.status_code == 200
    assert response.json()["title"] == "New"
    assert response.json()["course_ids"] == [course]


def test_omitted_fields_are_kept_and_null_is_422(client):
    course = generate(client)["course"]["id"]
    goal = client.post("/api/goals", json={"title": "Keep"}).json()["id"]
    client.put(f"/api/goals/{goal}", json={"course_ids": [course]})

    assert client.put(f"/api/goals/{goal}", json={"title": "Renamed"}).json()["course_ids"] == [course]
    assert client.put(f"/api/goals/{goal}", json={"course_ids": []}).json()["title"] == "Renamed"
    assert client.put(f"/api/goals/{goal}", json={"title": None}).status_code == 422


def test_a_course_moves_from_one_goal_to_another(client):
    a = generate(client)["course"]["id"]
    b = generate(client, "Physics")["course"]["id"]
    first = client.post("/api/goals", json={"title": "First"}).json()["id"]
    second = client.post("/api/goals", json={"title": "Second"}).json()["id"]
    client.put(f"/api/goals/{first}", json={"course_ids": [a, b]})

    client.put(f"/api/goals/{second}", json={"course_ids": [b]})

    goals = {g["id"]: g["course_ids"] for g in client.get("/api/goals").json()}
    assert goals == {first: [a], second: [b]}


def test_unknown_course_or_goal_is_404(client):
    goal = client.post("/api/goals", json={"title": "G"}).json()["id"]

    assert client.put(f"/api/goals/{goal}", json={"course_ids": [999]}).json()["detail"] == "course not found"
    assert client.put("/api/goals/999", json={"title": "x"}).json()["detail"] == "goal not found"
    assert client.delete("/api/goals/999").status_code == 404


def test_delete_frees_its_courses(client):
    course = generate(client)["course"]["id"]
    goal = client.post("/api/goals", json={"title": "G"}).json()["id"]
    client.put(f"/api/goals/{goal}", json={"course_ids": [course]})

    assert client.delete(f"/api/goals/{goal}").status_code == 204
    assert client.get("/api/goals").json() == []
    # Room for a new one again.
    assert client.post("/api/goals", json={"title": "Next"}).status_code == 200
