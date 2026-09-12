"""Provider fallback: OpenCode quota stop must degrade to OpenRouter.

Regression: ``settings.llm_provider`` picked exactly one provider at startup, so
with an OpenCode key present OpenRouter was never called — "OpenCode habis
limit" meant OCR and the AI advisor were simply down.
"""

import time

import httpx
import pytest

from app.core.config import settings
from app.core.llm import CHAT_MODELS, chat_plan, is_retryable_status, vision_plan


@pytest.fixture
def both_keys(monkeypatch):
    monkeypatch.setattr(settings, "OPENCODE_GO_API_KEY", "sk-opencode-test", raising=False)
    monkeypatch.setattr(settings, "OPENROUTER_API_KEY", "sk-or-test", raising=False)
    return settings


class TestPlan:
    def test_opencode_first_then_openrouter(self, both_keys):
        assert [a.provider for a in chat_plan("flash")] == ["opencode", "openrouter"]
        assert [a.provider for a in vision_plan()] == ["opencode", "openrouter"]

    def test_model_ids_are_mapped_per_provider(self, both_keys):
        flash = {a.provider: a.model for a in chat_plan("flash")}
        assert flash["opencode"] == "deepseek-v4.1-flash"
        assert flash["openrouter"] == "deepseek/deepseek-v4.1-flash"

        advanced = {a.provider: a.model for a in chat_plan("advanced")}
        assert advanced["opencode"] == "deepseek-v4-pro"
        assert advanced["openrouter"] == "deepseek/deepseek-v4-pro"

        vision = {a.provider: a.model for a in vision_plan()}
        assert vision["openrouter"] == "deepseek/deepseek-v4-flash-vision-exp"

    def test_opus_is_gone(self, both_keys):
        """Legacy 'opus' alias was removed — unknown aliases pass through raw."""
        assert "opus" not in CHAT_MODELS["opencode"]
        assert "opus" not in CHAT_MODELS["openrouter"]
        assert [a.model for a in chat_plan("opus")] == ["opus", "opus"]

    def test_openrouter_only_when_opencode_key_absent(self, monkeypatch):
        monkeypatch.setattr(settings, "OPENCODE_GO_API_KEY", "", raising=False)
        monkeypatch.setattr(settings, "OPENROUTER_API_KEY", "sk-or-test", raising=False)
        assert [a.provider for a in chat_plan("advanced")] == ["openrouter"]

    def test_headers_carry_provider_specific_extras(self, both_keys):
        plan = {a.provider: a.headers for a in chat_plan("flash")}
        assert plan["openrouter"]["HTTP-Referer"] == "https://wealthtrack.filla.id"
        assert "x-opencode-session" in plan["opencode"]

    def test_retryable_statuses(self):
        for status in (401, 403, 408, 429, 500, 503):
            assert is_retryable_status(status)
        assert not is_retryable_status(200)
        assert not is_retryable_status(422)


class _FakeResponse:
    def __init__(self, status_code, payload=None):
        self.status_code = status_code
        self._payload = payload or {}
        self.text = str(payload)

    def json(self):
        return self._payload


@pytest.fixture
def fake_post(monkeypatch):
    """Route fake responses per URL, recording the order of attempts."""
    calls: list[str] = []
    responses: dict[str, _FakeResponse] = {}

    async def _post(self, url, **kwargs):
        calls.append(url)
        return responses[url]

    monkeypatch.setattr(httpx.AsyncClient, "post", _post)
    return calls, responses


class TestChatFallback:
    async def test_falls_back_when_primary_is_limited(self, both_keys, fake_post, monkeypatch):
        from app.core.llm import OPENCODE_URL, OPENROUTER_URL
        from app.services import ai_advisor_service as svc

        calls, responses = fake_post
        responses[OPENCODE_URL] = _FakeResponse(429, {"error": "quota"})
        responses[OPENROUTER_URL] = _FakeResponse(
            200, {"choices": [{"message": {"content": "halo dari openrouter"}}]}
        )

        out = await svc.call_model([{"role": "user", "content": "hai"}], model="flash")

        assert out == "halo dari openrouter"
        assert calls == [OPENCODE_URL, OPENROUTER_URL]

    async def test_all_providers_limited_raises_quota_message(self, both_keys, fake_post):
        from app.core.llm import OPENCODE_URL, OPENROUTER_URL
        from app.services import ai_advisor_service as svc

        calls, responses = fake_post
        responses[OPENCODE_URL] = _FakeResponse(429, {"error": "quota"})
        responses[OPENROUTER_URL] = _FakeResponse(429, {"error": "quota"})

        with pytest.raises(Exception) as err:
            await svc.call_model([{"role": "user", "content": "hai"}], model="flash")
        assert "batas pemakaian" in str(err.value)
        assert calls == [OPENCODE_URL, OPENROUTER_URL]

    async def test_network_error_on_primary_falls_back(self, both_keys, monkeypatch):
        from app.core.llm import OPENCODE_URL, OPENROUTER_URL
        from app.services import ai_advisor_service as svc

        calls: list[str] = []

        async def _post(self, url, **kwargs):
            calls.append(url)
            if url == OPENCODE_URL:
                raise httpx.ConnectError("boom")
            return _FakeResponse(200, {"choices": [{"message": {"content": "ok"}}]})

        monkeypatch.setattr(httpx.AsyncClient, "post", _post)
        assert await svc.call_model([{"role": "user", "content": "hai"}]) == "ok"
        assert calls == [OPENCODE_URL, OPENROUTER_URL]


class TestOcrFallback:
    async def test_vision_falls_back_when_primary_is_limited(
        self, both_keys, fake_post, monkeypatch
    ):
        from app.core.llm import OPENCODE_URL, OPENROUTER_URL
        from app.services.ocr_service import OcrService

        calls, responses = fake_post
        responses[OPENCODE_URL] = _FakeResponse(429, {"error": "quota"})
        responses[OPENROUTER_URL] = _FakeResponse(
            200,
            {"choices": [{"message": {"content": '```json\n{"amount": 5000}\n```'}}]},
        )
        svc = OcrService(db=None)  # type: ignore[arg-type]

        out = await svc._call_vision_api_with_retry("data:image/jpeg;base64,AAA", "prompt")

        assert out.strip() == '{"amount": 5000}'
        assert calls == [OPENCODE_URL, OPENROUTER_URL]

    async def test_vision_quota_on_all_providers_raises(self, both_keys, fake_post):
        from app.core.llm import OPENCODE_URL, OPENROUTER_URL
        from app.services.ocr_service import OcrService, OcrVisionApiError

        calls, responses = fake_post
        responses[OPENCODE_URL] = _FakeResponse(429, {"error": "quota"})
        responses[OPENROUTER_URL] = _FakeResponse(429, {"error": "quota"})
        svc = OcrService(db=None)  # type: ignore[arg-type]

        with pytest.raises(OcrVisionApiError) as err:
            await svc._call_vision_api_with_retry("data:image/jpeg;base64,AAA", "prompt")
        assert err.value.status_code == 429
        assert calls == [OPENCODE_URL, OPENROUTER_URL]


class TestTokenBudget:
    def test_budgets_come_from_settings(self, monkeypatch):
        from app.core.llm import chat_max_tokens, vision_max_tokens

        monkeypatch.setattr(settings, "LLM_MAX_TOKENS_CHAT", 5000, raising=False)
        monkeypatch.setattr(settings, "LLM_MAX_TOKENS_VISION", 7000, raising=False)
        assert chat_max_tokens() == 5000
        assert chat_max_tokens(scale=2) == 10000  # retry doubles the cap
        assert vision_max_tokens() == 7000

    async def test_empty_answer_because_of_length_is_retried_bigger(
        self, both_keys, monkeypatch
    ):
        """finish_reason=length + no text (all budget spent on reasoning) → retry."""
        from app.core.llm import OPENCODE_URL
        from app.services import ai_advisor_service as svc

        seen: list[int] = []

        async def _post(self, url, **kwargs):
            seen.append(kwargs["json"]["max_tokens"])
            if len(seen) == 1:
                return _FakeResponse(
                    200,
                    {
                        "choices": [
                            {
                                "finish_reason": "length",
                                "message": {"content": None},
                            }
                        ]
                    },
                )
            return _FakeResponse(
                200,
                {
                    "choices": [
                        {"finish_reason": "stop", "message": {"content": "jawaban lengkap"}}
                    ]
                },
            )

        monkeypatch.setattr(httpx.AsyncClient, "post", _post)
        out = await svc.call_model([{"role": "user", "content": "hai"}])

        assert out == "jawaban lengkap"
        assert len(seen) == 2
        assert seen[1] == seen[0] * 2
        assert seen[0] == settings.LLM_MAX_TOKENS_CHAT

    async def test_vision_uses_configured_budget(self, both_keys, monkeypatch):
        from app.core.llm import OPENCODE_URL
        from app.services.ocr_service import OcrService

        monkeypatch.setattr(settings, "LLM_MAX_TOKENS_VISION", 1234, raising=False)
        seen: list[int] = []

        async def _post(self, url, **kwargs):
            seen.append(kwargs["json"]["max_tokens"])
            return _FakeResponse(
                200, {"choices": [{"message": {"content": '{"amount": 1}'}}]}
            )

        monkeypatch.setattr(httpx.AsyncClient, "post", _post)
        svc = OcrService(db=None)  # type: ignore[arg-type]
        await svc._call_vision_api_with_retry("data:image/jpeg;base64,AAA", "prompt")

        assert seen == [1234]


class TestOcrImageSweep:
    def test_removes_only_old_images(self, tmp_path, monkeypatch):
        from app.services.ocr_service import sweep_ocr_images

        monkeypatch.setattr(settings, "OCR_IMAGE_DIR", str(tmp_path), raising=False)
        stale = tmp_path / "ocr_1_20260101_000000.jpg"
        fresh = tmp_path / "ocr_1_20990101_000000.jpg"
        stale.write_bytes(b"x")
        fresh.write_bytes(b"x")
        old = time.time() - (48 * 3600)
        import os

        os.utime(stale, (old, old))

        removed = sweep_ocr_images(max_age_hours=24)

        assert removed == 1
        assert not stale.exists()
        assert fresh.exists()

    def test_missing_dir_is_not_an_error(self, tmp_path, monkeypatch):
        from app.services.ocr_service import sweep_ocr_images

        monkeypatch.setattr(
            settings, "OCR_IMAGE_DIR", str(tmp_path / "nope"), raising=False
        )
        assert sweep_ocr_images() == 0
