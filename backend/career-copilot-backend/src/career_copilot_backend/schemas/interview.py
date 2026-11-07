from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from career_copilot_backend.schemas.analysis import AnalysisModel


class InterviewCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    resume_id: UUID
    job_description: str = Field(min_length=1, max_length=20_000)

    @field_validator("job_description")
    @classmethod
    def nonblank_description(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("Job description cannot be empty")
        return value


class InterviewAnswer(BaseModel):
    model_config = ConfigDict(extra="forbid")
    answer: str = Field(min_length=1, max_length=4000)

    @field_validator("answer")
    @classmethod
    def nonblank_answer(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("Answer cannot be empty")
        return value


class InterviewResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    resume_id: UUID
    job_description: str
    status: Literal["draft", "ready"]
    created_at: datetime
    updated_at: datetime


class InterviewPage(BaseModel):
    items: list[InterviewResponse]
    limit: int
    offset: int


class QuestionResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    session_id: UUID
    sequence: int
    prompt: str
    answer: str | None
    feedback: dict | None
    created_at: datetime


class QuestionPage(BaseModel):
    items: list[QuestionResponse]
    limit: int
    offset: int


class GeneratedQuestion(AnalysisModel):
    prompt: str = Field(min_length=1, max_length=500)


class InterviewQuestions(AnalysisModel):
    questions: list[GeneratedQuestion] = Field(min_length=3, max_length=3)


class RubricItem(AnalysisModel):
    rating: Literal["strong", "developing", "needs_work", "not_assessable"]
    explanation: str = Field(min_length=1, max_length=1000)


class InterviewFeedback(AnalysisModel):
    correctness: RubricItem
    completeness: RubricItem
    relevance: RubricItem
    clarity: RubricItem
    strengths: list[str] = Field(max_length=5)
    improvements: list[str] = Field(max_length=5)
    example_answer: str = Field(min_length=1, max_length=4000)


class InterviewJobRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    allow_provider_fallbacks: bool = False


class InterviewJobResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    session_id: UUID
    question_id: UUID | None
    kind: Literal["generation", "feedback"]
    status: Literal["queued", "running", "completed", "failed"]
    error_code: str | None
