"""Every agent prompt asks for English output and carries no Korean (docs/english-strings.md section 7)."""

import re

import pytest

from app.agents import (
    auditor,
    challenger,
    checkin_converter,
    clarifier,
    front_desk,
    linker,
    material_finder,
    narrator,
    planner,
    recommender,
    recorder,
    syllabus,
)
from app.llm.base import agent_of

HANGUL = re.compile(r"[가-힣]")

PROMPTS = {
    "auditor": auditor.SYSTEM_PROMPT,
    "challenger": challenger.SYSTEM_PROMPT,
    "checkin_converter": checkin_converter.SYSTEM_PROMPT,
    "clarifier": clarifier.SYSTEM_PROMPT,
    "front_desk": front_desk.SYSTEM_PROMPT,
    "linker": linker.SYSTEM_PROMPT,
    "material_finder (queries)": material_finder.QUERY_PROMPT,
    "material_finder (pick)": material_finder.PICK_PROMPT,
    "narrator": narrator.SYSTEM_PROMPT,
    "planner": planner.SYSTEM_PROMPT,
    "recommender": recommender.SYSTEM_PROMPT,
    "recorder": recorder.SYSTEM_PROMPT,
    "syllabus_finder": syllabus.SYSTEM_PROMPT,
}


@pytest.mark.parametrize("name", PROMPTS)
def test_prompt_has_no_korean_and_asks_for_english(name):
    prompt = PROMPTS[name]

    assert not HANGUL.search(prompt), name
    assert "English" in prompt, name
    assert "해요체" not in prompt and "in Korean" not in prompt


@pytest.mark.parametrize("name", [n for n in PROMPTS if "(" not in n])
def test_prompt_still_starts_with_its_agent_tag(name):
    assert agent_of([{"role": "system", "content": PROMPTS[name]}]) == name
