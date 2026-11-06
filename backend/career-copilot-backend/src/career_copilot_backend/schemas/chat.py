from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from career_copilot_backend.schemas.rag import Citation


class ConversationCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: str = Field(default="New chat", min_length=1, max_length=100)

    @field_validator("title")
    @classmethod
    def trim_title(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Title cannot be empty")
        return value


class MessageCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    content: str = Field(min_length=1, max_length=4000)

    @field_validator("content")
    @classmethod
    def reject_blank(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("Message cannot be empty")
        return value


class ConversationResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    title: str
    created_at: datetime
    updated_at: datetime


class MessageResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    conversation_id: UUID
    sequence: int
    role: Literal["user", "assistant"]
    content: str
    citations: list[Citation] = Field(default_factory=list)
    insufficient_information: bool | None = None
    reply_to_id: UUID | None = None
    created_at: datetime


class AnswerRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    message_id: UUID
    allow_provider_fallbacks: bool = False


class AnswerRetry(BaseModel):
    model_config = ConfigDict(extra="forbid")
    allow_provider_fallbacks: bool = False


class AnswerJobResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    conversation_id: UUID
    question_id: UUID
    status: Literal["queued", "running", "completed", "failed"]
    answer_message_id: UUID | None = None
    error_code: str | None = None


class ConversationPage(BaseModel):
    items: list[ConversationResponse]
    limit: int
    offset: int


class MessagePage(BaseModel):
    items: list[MessageResponse]
    limit: int
    offset: int
