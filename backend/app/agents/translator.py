"""Translator: puts an already generated course into another language.

When the player switches the app's language, the courses made before keep the language they
were generated in. This agent rewrites what the app shows of one course — its title, each
node's title and description, each leaf's knowledge points — in the new language, in one call
per course, keyed by the same ids it was given. Nothing else of the course changes.

The answer is all or nothing: a node missing, a field empty, a point list of another length,
and the whole course is refused (TranslatorError) so the caller leaves it as it was.
"""

import json
import logging

from app.llm.base import LLMProvider, Message, agent_tag, complete_with_json_retry

logger = logging.getLogger(__name__)

LANGUAGE_NAMES = {"en": "English", "zh": "Simplified Chinese (简体中文)", "ko": "Korean (한국어)"}

SYSTEM_PROMPT = (
    agent_tag("translator")
    + """
Translate the texts of one learning course into {language}. The user
message is JSON: the course title, and its nodes keyed by id, each with a
title, a description and (for some) a list of knowledge points.

- Translate every title, description and point into {language}, as a
  textbook in that language would name them. Keep established technical
  terms, formulas, code and proper names as such a textbook keeps them.
- A text already in {language} stays as it is.
- Keep every id, every key and the number and order of points exactly as
  given; add nothing and leave nothing out.

Output only JSON in the same shape:
{{"course": {{"title": "..."}}, "nodes": {{"<id>": {{"title": "...",
"description": "...", "points": ["..."]}}}}}}
"""
)


class TranslatorError(Exception):
    """The model's answer was not a complete translation of the course."""


class Translator:
    def __init__(self, provider: LLMProvider):
        self._provider = provider

    def translate(self, language: str, course: dict) -> dict:
        """[course] (`{"course": {"title"}, "nodes": {id: {"title", "description", "points"?}}}`)
        with every text in [language], same ids and shape. Raises TranslatorError when the
        answer is not valid JSON or leaves anything out."""
        messages: list[Message] = [
            {"role": "system", "content": SYSTEM_PROMPT.format(language=LANGUAGE_NAMES[language])},
            {"role": "user", "content": json.dumps(course, ensure_ascii=False)},
        ]
        logger.info("translator.translate() calling provider=%s", self._provider.name)
        raw = complete_with_json_retry(self._provider, messages)
        try:
            data = json.loads(raw)
        except (json.JSONDecodeError, TypeError) as exc:
            raise TranslatorError("not JSON") from exc
        return _checked(course, data)


def _text(value, *, allow_empty: bool = False) -> str:
    if not isinstance(value, str):
        raise TranslatorError("a text is not a string")
    text = value.strip()
    if not text and not allow_empty:
        raise TranslatorError("a text is empty")
    return text


def _checked(source: dict, data) -> dict:
    """The translation of [source] read from [data], or TranslatorError."""
    if not isinstance(data, dict):
        raise TranslatorError("not an object")
    course = data.get("course")
    nodes = data.get("nodes")
    if not isinstance(course, dict) or not isinstance(nodes, dict):
        raise TranslatorError("course or nodes missing")
    out = {"course": {"title": _text(course.get("title"))}, "nodes": {}}
    for node_id, original in source["nodes"].items():
        node = nodes.get(str(node_id))
        if not isinstance(node, dict):
            raise TranslatorError(f"node {node_id} missing")
        translated = {
            "title": _text(node.get("title")),
            "description": _text(node.get("description"), allow_empty=not original["description"].strip()),
        }
        if "points" in original:
            points = node.get("points")
            if not isinstance(points, list) or len(points) != len(original["points"]):
                raise TranslatorError(f"node {node_id} points do not match")
            translated["points"] = [_text(p) for p in points]
            if len({p.casefold() for p in translated["points"]}) != len(translated["points"]):
                raise TranslatorError(f"node {node_id} points are not distinct")
        out["nodes"][str(node_id)] = translated
    return out
