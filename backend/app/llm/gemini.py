from google import genai

from app.config import settings
from app.llm.base import Message


class GeminiEmptyResponseError(RuntimeError):
    """Gemini 返回了空响应，例如被安全过滤器拦截。"""


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
        text = response.text
        if not text:
            raise GeminiEmptyResponseError("Gemini 返回了空响应，可能被安全过滤器拦截")
        return self._strip_code_fence(text)

    @staticmethod
    def _strip_code_fence(text: str) -> str:
        stripped = text.strip()
        if not stripped.startswith("```"):
            return stripped
        lines = stripped.splitlines()
        if len(lines) >= 2 and lines[-1].strip() == "```":
            lines = lines[1:-1]
        else:
            lines = lines[1:]
        return "\n".join(lines).strip()
