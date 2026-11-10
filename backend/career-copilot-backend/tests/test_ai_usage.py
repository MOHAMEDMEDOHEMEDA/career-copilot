from decimal import Decimal
from uuid import uuid4

import httpx
import pytest
import test_auth
from sqlalchemy import select
from sqlalchemy.orm import sessionmaker

from career_copilot_backend.llm.usage import (
    capture_usage,
    provider_attempt,
    record_response,
)
from career_copilot_backend.models import AIUsage

client = test_auth.client


def test_usage_is_private_and_tracks_unknown_costs(client):
    api, engine = client
    credentials = [
        {"email": "one@example.com", "password": "synthetic-password"},
        {"email": "two@example.com", "password": "synthetic-password"},
    ]
    headers = []
    user_ids = []
    for item in credentials:
        user_ids.append(api.post("/api/v1/auth/register", json=item).json()["id"])
        token = api.post("/api/v1/auth/login", json=item).json()["access_token"]
        headers.append({"Authorization": f"Bearer {token}"})
    from uuid import UUID

    sessions = sessionmaker(bind=engine)
    with capture_usage(sessions, UUID(user_ids[0]), "adaptive_next", uuid4()):
        with provider_attempt("openrouter", "openrouter/free") as event:
            record_response(event, {"model": "vendor/model:free", "usage": {"prompt_tokens": 100, "completion_tokens": 30, "cost": 0}}, "openrouter")
        with provider_attempt("gemini", "gemini-2.5-flash-lite") as event:
            record_response(event, {"usageMetadata": {"promptTokenCount": 10, "candidatesTokenCount": 2}}, "gemini")
    response = api.get("/api/v1/ai-usage?limit=1", headers=headers[0])
    assert response.status_code == 200
    assert response.json()["summary"] == {"attempts": 2, "known_input_tokens": 110, "known_output_tokens": 32, "attempts_with_unknown_tokens": 0, "known_cost_usd": 0.0, "attempts_with_unknown_cost": 1}
    assert len(response.json()["items"]) == 1
    assert api.get("/api/v1/ai-usage", headers=headers[1]).json()["summary"]["attempts"] == 0
    assert api.get("/api/v1/ai-usage").status_code == 401


def test_attempt_records_failure_without_raw_content(client):
    api, engine = client
    from uuid import UUID
    user_id = UUID(api.post("/api/v1/auth/register", json={"email": "person@example.com", "password": "synthetic-password"}).json()["id"])
    sessions = sessionmaker(bind=engine)
    with pytest.raises(ValueError), capture_usage(sessions, user_id, "resume_analysis", uuid4()), provider_attempt("ollama", "unsafe model with spaces"):
        raise ValueError("synthetic private input")
    with sessions() as session:
        item = session.scalar(select(AIUsage))
        assert item is not None and item.outcome == "failed" and item.model is None
        assert item.cost_usd is None
        assert "synthetic private input" not in str(item.__dict__)


def test_configured_gemini_estimate_and_local_cost(monkeypatch):
    from career_copilot_backend.core.config import settings
    monkeypatch.setattr(settings, "gemini_input_usd_per_million", 0.1)
    monkeypatch.setattr(settings, "gemini_output_usd_per_million", 0.4)
    event = {}
    record_response(event, {"usageMetadata": {"promptTokenCount": 3000, "candidatesTokenCount": 700}}, "gemini")
    assert event["cost_usd"] == Decimal("0.00058")
    assert event["cost_basis"] == "configured_estimate"
    event = {}
    record_response(event, {}, "ollama")
    assert event["cost_usd"] == 0 and event["cost_basis"] == "local_inference"


@pytest.mark.asyncio
async def test_fallback_provider_attempts_are_tracked(client):
    from uuid import UUID

    from career_copilot_backend.llm.alternatives import FallbackProvider, OllamaProvider
    from career_copilot_backend.llm.openrouter import OpenRouterProvider

    api, engine = client
    user_id = UUID(api.post("/api/v1/auth/register", json={"email": "fallback@example.com", "password": "synthetic-password"}).json()["id"])
    sessions = sessionmaker(bind=engine)

    def handler(request):
        if request.url.host == "openrouter.ai":
            return httpx.Response(429)
        return httpx.Response(200, json={"message": {"content": "{}"}, "prompt_eval_count": 12, "eval_count": 3})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        chain = FallbackProvider([OpenRouterProvider("synthetic-key", http), OllamaProvider("http://localhost:11434", "local-model", http)])
        with capture_usage(sessions, user_id, "chat_answer", uuid4()):
            assert await chain.generate_structured(system_instruction="instruction", untrusted_text="synthetic private input", output_schema={"type": "object"}, max_output_tokens=10) == "{}"
    with sessions() as session:
        events = list(session.scalars(select(AIUsage).order_by(AIUsage.provider)))
        assert len(events) == 2
        assert events[0].provider == "ollama" and events[0].input_tokens == 12
        assert events[1].provider == "openrouter" and events[1].outcome == "failed"
        assert all("synthetic private input" not in str(event.__dict__) for event in events)
