"""What the text agents cost (contract #46): every call to a real provider is logged as it
returns (LLMCall, app/llm/usage.py); this prices the log for the developer panel. No LLM.

List prices of 2026-10-12, in dollars per million tokens: input, cached input, output
(developers.openai.com/api/docs/pricing, platform.claude.com/docs/en/about-claude/pricing).
A model that is not here has no cost: its calls are counted, and left out of every cost sum and
average.
"""

from collections import Counter, defaultdict
from collections.abc import Iterable

from sqlmodel import Session, col, select

from app.models import LLMCall

PRICES = {
    "gpt-6-luna": (0.10, 0.01, 0.50),
    "gpt-6-sol": (1.25, 0.125, 10.0),
    # Its rate for prompts up to 100,000 tokens; a longer prompt costs more, which is not
    # told apart here.
    "claude-haiku-5-5": (0.10, 0.01, 0.50),
    "claude-sonnet-5-5": (2.0, 0.10, 10.0),
    "claude-opus-5-5": (4.0, 0.20, 20.0),
    # Text to speech (app/services/voice.py): text in, audio out. The audio tokens are
    # estimated from the length of the audio, see SPEECH_TOKENS_PER_SECOND there.
    "gpt-4o-mini-tts": (0.60, 0.60, 12.0),
}
# The agent name speech is logged under, and the models that are not text models: left out
# where calls are priced on another model.
SPEECH_AGENT = "speech"
SPEECH_MODELS = frozenset({"gpt-4o-mini-tts"})


def provider_of(model: str) -> str:
    return "claude" if model.startswith("claude") else "openai"


def tokens_cost(prices: tuple[float, float, float], input_tokens: int, cached_tokens: int, output_tokens: int) -> float:
    """Dollars. [input_tokens] counts every prompt token, the cached ones included."""
    p_in, p_cached, p_out = prices
    return (max(input_tokens - cached_tokens, 0) * p_in + cached_tokens * p_cached + output_tokens * p_out) / 1_000_000


def call_cost(call: LLMCall) -> float | None:
    """Dollars for one call; None when its model has no price here. A failed call costs nothing."""
    prices = PRICES.get(call.model)
    if prices is None:
        return None
    return tokens_cost(prices, call.input_tokens, call.cached_tokens, call.output_tokens)


def calls_cost(calls: Iterable[LLMCall]) -> float | None:
    """Dollars for the calls that have a price; None when none of them has."""
    costs = [c for c in map(call_cost, calls) if c is not None]
    return sum(costs) if costs else None


def _dollars(value: float | None) -> float | None:
    return None if value is None else round(value, 6)


def _mean(values: list[float]) -> float | None:
    return sum(values) / len(values) if values else None


def _whole(value: float | None) -> int | None:
    return None if value is None else round(value)


def _cost_fields(calls: list[LLMCall]) -> dict:
    """`cost`: the sum over the priced calls; `avg_cost`: dollars per priced call that succeeded."""
    priced = [c for c in (call_cost(call) for call in calls if call.ok) if c is not None]
    return {"cost": _dollars(calls_cost(calls)), "avg_cost": _dollars(_mean(priced))}


def _by_cost(rows: list[dict], key: str = "cost") -> list[dict]:
    """Highest first; rows without a cost last."""
    return sorted(rows, key=lambda r: (r[key] is None, -(r[key] or 0)))


def _provider_row(provider: str, model: str, calls: list[LLMCall]) -> dict:
    ok = [c for c in calls if c.ok]
    return {
        "provider": provider,
        "model": model,
        "calls": len(calls),
        "failed": len(calls) - len(ok),
        "input_tokens": sum(c.input_tokens for c in calls),
        "cached_tokens": sum(c.cached_tokens for c in calls),
        "output_tokens": sum(c.output_tokens for c in calls),
        "avg_ms": _whole(_mean([c.elapsed_ms for c in ok])),
        **_cost_fields(calls),
    }


def _agent_row(agent: str, provider: str, model: str, calls: list[LLMCall]) -> dict:
    ok = [c for c in calls if c.ok]
    return {
        "agent": agent,
        "provider": provider,
        "model": model,
        "calls": len(calls),
        "avg_input_tokens": _whole(_mean([c.input_tokens for c in ok])),
        "avg_output_tokens": _whole(_mean([c.output_tokens for c in ok])),
        "avg_ms": _whole(_mean([c.elapsed_ms for c in ok])),
        **_cost_fields(calls),
    }


def _audit_rows(calls: list[LLMCall]) -> list[dict]:
    """The calls made for an audit, by audit, then by the provider and model the audit ran on:
    the one most of its calls used (the earlier one on a tie)."""
    by_audit: dict[int, list[LLMCall]] = defaultdict(list)
    for call in calls:
        if call.audit_id is not None:
            by_audit[call.audit_id].append(call)
    groups: dict[tuple[str, str], list[list[LLMCall]]] = defaultdict(list)
    for audit_calls in by_audit.values():
        ran_on = Counter((c.provider, c.model) for c in audit_calls).most_common(1)[0][0]
        groups[ran_on].append(audit_calls)
    rows = []
    for (provider, model), audits in groups.items():
        # An audit's cost is known when every call of it that succeeded has a price.
        costs = [
            sum(call_cost(c) or 0 for c in audit_calls)
            for audit_calls in audits
            if all(call_cost(c) is not None for c in audit_calls if c.ok)
        ]
        rows.append(
            {
                "provider": provider,
                "model": model,
                "audits": len(audits),
                "avg_calls": round(sum(len(a) for a in audits) / len(audits), 2),
                "avg_cost": _dollars(_mean(costs)),
            }
        )
    return _by_cost(rows, "avg_cost")


def all_on(calls: list[LLMCall]) -> list[dict]:
    """What the text calls would have cost had every one of them run on one model, for each
    text model with a price, cheapest first. Same tokens, that model's price; a call's cached
    tokens count as cached only on its own provider (another one's cache would not have had
    them, and the Claude provider here does not cache). Speech is left out."""
    text = [c for c in calls if c.ok and c.agent != SPEECH_AGENT]
    if not text:
        return []
    rows = []
    for model, prices in PRICES.items():
        if model in SPEECH_MODELS:
            continue
        provider = provider_of(model)
        cost = sum(
            tokens_cost(prices, c.input_tokens, c.cached_tokens if c.provider == provider else 0, c.output_tokens)
            for c in text
        )
        rows.append({"provider": provider, "model": model, "cost": round(cost, 6)})
    return sorted(rows, key=lambda r: r["cost"])


def overview(session: Session) -> dict:
    calls = list(session.exec(select(LLMCall).order_by(col(LLMCall.created_at), col(LLMCall.id))).all())
    by_model: dict[tuple[str, str], list[LLMCall]] = defaultdict(list)
    by_agent: dict[tuple[str, str, str], list[LLMCall]] = defaultdict(list)
    for call in calls:
        by_model[(call.provider, call.model)].append(call)
        by_agent[(call.agent, call.provider, call.model)].append(call)
    ok = [c for c in calls if c.ok]
    totals = {
        "calls": len(calls),
        "failed": len(calls) - len(ok),
        **_cost_fields(calls),
        # Calls that succeeded on a model without a price: in no cost above or below.
        "unpriced_calls": sum(1 for c in ok if call_cost(c) is None),
    }
    totals["cost"] = totals["cost"] or 0.0
    return {
        "totals": totals,
        "providers": _by_cost([_provider_row(*key, rows) for key, rows in by_model.items()]),
        "agents": _by_cost([_agent_row(*key, rows) for key, rows in by_agent.items()]),
        "audits": _audit_rows(calls),
        "all_on": all_on(calls),
    }
