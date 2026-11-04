from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class ResumeResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    filename: str
    text: str
    created_at: datetime
    updated_at: datetime


class ResumeUpdate(BaseModel):
    text: str = Field(min_length=1, max_length=1_000_000)


class ResumePage(BaseModel):
    items: list[ResumeResponse]
    limit: int
    offset: int
