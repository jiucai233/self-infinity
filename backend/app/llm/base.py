from typing import Protocol, TypedDict


class Message(TypedDict):
    role: str  # "system" | "user" | "assistant"
    content: str


class LLMProvider(Protocol):
    name: str

    def complete(self, messages: list[Message]) -> str:
        """Return a raw text completion. Callers are responsible for parsing JSON out of it."""
        ...
