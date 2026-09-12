"""LLM provider plan: primary provider first, then the fallback key.

Both the AI advisor (chat) and receipt OCR (vision) go through here so that a
quota stop / 429 / outage on one provider degrades to the other instead of
failing the user's request. Before this module the app picked ONE provider at
startup (``settings.llm_provider``): with an OpenCode key present, OpenRouter
was never called, so "OpenCode limit" meant "feature down".
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass

from app.core.config import settings

OPENCODE_URL = "https://opencode.ai/zen/go/v1/chat/completions"
OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"

# Chat model aliases per provider (keys come from the client: flash/advanced).
CHAT_MODELS: dict[str, dict[str, str]] = {
    "opencode": {
        "flash": "deepseek-v4-flash",
        "advanced": "deepseek-v4-pro",
        "opus": "deepseek-v4-pro",  # legacy APK
    },
    "openrouter": {
        "flash": "deepseek/deepseek-v4-flash",
        "advanced": "deepseek/deepseek-v4-pro",
        "opus": "deepseek/deepseek-v4-pro",  # legacy APK
    },
}

VISION_MODELS: dict[str, str] = {
    "opencode": "deepseek-v4-flash-vision-exp",
    "openrouter": "deepseek/deepseek-v4-flash-vision-exp",
}


@dataclass(frozen=True)
class LlmAttempt:
    """One provider attempt: where to send it and which model id to use."""

    provider: str
    url: str
    key: str
    headers: dict
    model: str


def _headers(provider: str, key: str) -> dict:
    headers = {
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "User-Agent": "wealthtrack-backend/1.0",
    }
    if provider == "openrouter":
        headers["HTTP-Referer"] = "https://wealthtrack.filla.id"
        headers["X-Title"] = "WealthTrack"
    else:
        # OpenCode Go requires identifying UA + session id for routing.
        headers["x-opencode-session"] = str(uuid.uuid4())
    return headers


def _providers() -> list[str]:
    """Configured providers, primary first.

    OpenCode stays primary while its key exists (it is the cheaper path), but
    OpenRouter is now kept as an explicit second attempt instead of being
    ignored.
    """
    order: list[str] = []
    if settings.OPENCODE_GO_API_KEY:
        order.append("opencode")
    if settings.OPENROUTER_API_KEY:
        order.append("openrouter")
    return order


def _key_for(provider: str) -> str:
    if provider == "openrouter":
        return settings.OPENROUTER_API_KEY
    return settings.OPENCODE_GO_API_KEY


def _url_for(provider: str) -> str:
    return OPENROUTER_URL if provider == "openrouter" else OPENCODE_URL


def chat_plan(model: str = "flash") -> list[LlmAttempt]:
    """Ordered chat attempts for a client model alias."""
    out: list[LlmAttempt] = []
    for provider in _providers():
        mapped = CHAT_MODELS.get(provider, {})
        out.append(
            LlmAttempt(
                provider=provider,
                url=_url_for(provider),
                key=_key_for(provider),
                headers=_headers(provider, _key_for(provider)),
                model=mapped.get(model, model),
            )
        )
    return out


def vision_plan() -> list[LlmAttempt]:
    """Ordered vision (receipt OCR) attempts."""
    out: list[LlmAttempt] = []
    for provider in _providers():
        out.append(
            LlmAttempt(
                provider=provider,
                url=_url_for(provider),
                key=_key_for(provider),
                headers=_headers(provider, _key_for(provider)),
                model=VISION_MODELS.get(provider, VISION_MODELS["opencode"]),
            )
        )
    return out


def is_retryable_status(status: int) -> bool:
    """Statuses worth trying the next provider for.

    401/403 = bad or exhausted key on that provider, 429 = rate/quota limit,
    5xx/408/409 = their side is unhappy.
    """
    return status in (401, 403, 408, 409, 429) or status >= 500


def plan_configured() -> bool:
    """True when at least one provider key is available (so features can run)."""
    return bool(_providers())


def chat_max_tokens(scale: int = 1) -> int:
    """Output budget for chat calls (``scale`` doubles for a retry)."""
    base = int(getattr(settings, "LLM_MAX_TOKENS_CHAT", 32768) or 32768)
    return base * max(1, scale)


def vision_max_tokens() -> int:
    """Output budget for receipt OCR calls."""
    return int(getattr(settings, "LLM_MAX_TOKENS_VISION", 16384) or 16384)
