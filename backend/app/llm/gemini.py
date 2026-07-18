from google import genai

from app.config import settings
from app.llm.base import Message


class GeminiProvider:
    name = "gemini"

    def __init__(self) -> None:
        self._client = genai.Client(api_key=settings.gemini_api_key)

    def complete(self, messages: list[Message]) -> str:
        system = "\n".join(m["content"] for m in messages if m["role"] == "system")
        turns = [m for m in messages if m["role"] != "system"]
        contents = [
            {"role": "model" if m["role"] == "assistant" else "user", "parts": [{"text": m["content"]}]}
            for m in turns
        ]
        response = self._client.models.generate_content(
            model=settings.llm_model,
            contents=contents,
            config={
                "system_instruction": system,
                "response_mime_type": "application/json",
            },
        )
        return response.text
