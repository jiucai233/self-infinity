"""Clarifier：最多 2 个问题，任何失败都等于不需要澄清（UT-04、UT-05）。"""

import json

from app.agents.clarifier import Clarifier
from tests.helpers import BrokenProvider, ScriptedProvider


def clarifier_output(questions: list[str], needs: bool = True) -> str:
    return json.dumps({"needs_clarification": needs, "questions": questions}, ensure_ascii=False)


def test_ut04_more_than_two_questions_are_cut_to_two():
    provider = ScriptedProvider(clarifier=clarifier_output(["Question 1", "Question 2", "Question 3"]))

    result = Clarifier(provider).clarify("Statistics")

    assert result.needs_clarification is True
    assert result.questions == ["Question 1", "Question 2"]


def test_ut05_non_json_output_means_no_clarification():
    result = Clarifier(ScriptedProvider(clarifier="Yes, I need to ask")).clarify("Statistics")

    assert result.needs_clarification is False
    assert result.questions == []


def test_a_failing_provider_means_no_clarification():
    result = Clarifier(BrokenProvider()).clarify("Statistics")

    assert (result.needs_clarification, result.questions) == (False, [])


def test_true_with_no_questions_is_treated_as_false():
    result = Clarifier(ScriptedProvider(clarifier=clarifier_output([]))).clarify("Statistics")

    assert result.needs_clarification is False


def test_false_never_carries_questions():
    result = Clarifier(ScriptedProvider(clarifier=clarifier_output(["Question"], needs=False))).clarify("Statistics")

    assert (result.needs_clarification, result.questions) == (False, [])


def test_blank_questions_are_dropped():
    result = Clarifier(ScriptedProvider(clarifier=clarifier_output(["  ", "Question"]))).clarify("Statistics")

    assert result.questions == ["Question"]


def test_topic_is_the_user_message():
    provider = ScriptedProvider(clarifier=clarifier_output([], needs=False))

    Clarifier(provider).clarify("Probability and statistics")

    (messages,) = provider.calls_for("clarifier")
    assert messages[-1] == {"role": "user", "content": "Probability and statistics"}


# ---------------------------------------------------------------- 接口：POST /api/skills/clarify


def test_it_clarify_a_vague_topic_asks_one_question(client):
    response = client.post("/api/skills/clarify", json={"topic": "Statistics"})

    assert response.status_code == 200
    assert response.json() == {
        "needs_clarification": True,
        "questions": ["Do you mean high-school probability and statistics, or university-level statistics?"],
    }


def test_it_clarify_a_clear_topic_needs_nothing(client):
    response = client.post("/api/skills/clarify", json={"topic": "High School Math"})

    assert response.status_code == 200
    assert response.json() == {"needs_clarification": False, "questions": []}


def test_it_clarify_rejects_a_blank_topic(client):
    assert client.post("/api/skills/clarify", json={"topic": "   "}).status_code == 422
    assert client.post("/api/skills/clarify", json={}).status_code == 422


def test_it_clarify_failure_is_not_an_error(client, monkeypatch):
    monkeypatch.setattr("app.routers.skills.get_provider", lambda agent=None: BrokenProvider())

    response = client.post("/api/skills/clarify", json={"topic": "Statistics"})

    assert response.status_code == 200
    assert response.json() == {"needs_clarification": False, "questions": []}
