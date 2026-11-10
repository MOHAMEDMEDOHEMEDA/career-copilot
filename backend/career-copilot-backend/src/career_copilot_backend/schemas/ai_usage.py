from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict


class AIUsageItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    job_id: UUID
    operation: str
    provider: str
    model: str | None
    outcome: str
    input_tokens: int | None
    output_tokens: int | None
    cost_usd: float | None
    cost_basis: str | None
    created_at: datetime


class AIUsageSummary(BaseModel):
    attempts: int
    known_input_tokens: int
    known_output_tokens: int
    attempts_with_unknown_tokens: int
    known_cost_usd: float
    attempts_with_unknown_cost: int


class AIUsagePage(BaseModel):
    summary: AIUsageSummary
    items: list[AIUsageItem]
    limit: int
    offset: int
