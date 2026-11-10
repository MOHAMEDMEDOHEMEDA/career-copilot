"""Collect bounded provider metadata without retaining request or response content."""

import logging
import re
from collections.abc import Iterator
from contextlib import contextmanager
from contextvars import ContextVar
from decimal import Decimal, InvalidOperation
from typing import Any
from uuid import UUID

from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session, sessionmaker

from career_copilot_backend.core.config import settings
from career_copilot_backend.models.ai_usage import AIUsage

logger = logging.getLogger(__name__)
_events: ContextVar[list[dict[str, Any]] | None] = ContextVar("ai_usage", default=None)


def _count(value: Any) -> int | None:
    return value if type(value) is int and 0 <= value <= 1_000_000_000 else None


def _model(value: Any) -> str | None:
    if isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9_.:/-]{1,160}", value):
        return value
    return None


def _cost(value: Any) -> Decimal | None:
    if isinstance(value, bool) or not isinstance(value, (int, float, str)):
        return None
    try:
        amount = Decimal(str(value))
        return amount if amount.is_finite() and 0 <= amount <= 1_000_000 else None
    except InvalidOperation:
        return None


@contextmanager
def provider_attempt(provider: str, model: str | None = None) -> Iterator[dict[str, Any]]:
    event: dict[str, Any] = {"provider": provider, "model": _model(model), "outcome": "failed"}
    try:
        yield event
    finally:
        events = _events.get()
        if events is not None:
            events.append(event)


def record_response(event: dict[str, Any], body: dict[str, Any], provider: str) -> None:
    event["outcome"] = "response_received"
    if provider == "openrouter":
        event["model"] = _model(body.get("model")) or event.get("model")
        usage = body.get("usage") if isinstance(body.get("usage"), dict) else {}
        event["input_tokens"] = _count(usage.get("prompt_tokens"))
        event["output_tokens"] = _count(usage.get("completion_tokens"))
        amount = _cost(usage.get("cost"))
        if amount is not None:
            event.update(cost_usd=amount, cost_basis="provider_reported")
    elif provider == "ollama":
        event["input_tokens"] = _count(body.get("prompt_eval_count"))
        event["output_tokens"] = _count(body.get("eval_count"))
        event.update(cost_usd=Decimal(0), cost_basis="local_inference")
    elif provider == "gemini":
        usage = body.get("usageMetadata") if isinstance(body.get("usageMetadata"), dict) else {}
        event["input_tokens"] = _count(usage.get("promptTokenCount"))
        event["output_tokens"] = _count(usage.get("candidatesTokenCount"))
        thoughts = _count(usage.get("thoughtsTokenCount"))
        if thoughts is not None and event["output_tokens"] is not None:
            event["output_tokens"] += thoughts
        in_rate = settings.gemini_input_usd_per_million
        out_rate = settings.gemini_output_usd_per_million
        if in_rate is not None and out_rate is not None and event["input_tokens"] is not None and event["output_tokens"] is not None:
            estimate = (Decimal(event["input_tokens"]) * Decimal(str(in_rate)) + Decimal(event["output_tokens"]) * Decimal(str(out_rate))) / Decimal(1_000_000)
            if estimate <= Decimal(1_000_000):
                event.update(cost_usd=estimate, cost_basis="configured_estimate")


@contextmanager
def capture_usage(sessions: sessionmaker[Session], user_id: UUID | None, operation: str, job_id: UUID) -> Iterator[None]:
    events: list[dict[str, Any]] = []
    token = _events.set(events)
    try:
        yield
    finally:
        _events.reset(token)
        if user_id is not None and events:
            try:
                with sessions() as db:
                    db.add_all(AIUsage(user_id=user_id, job_id=job_id, operation=operation, **event) for event in events)
                    db.commit()
            except SQLAlchemyError:
                logger.warning("Unable to persist AI usage metadata")
