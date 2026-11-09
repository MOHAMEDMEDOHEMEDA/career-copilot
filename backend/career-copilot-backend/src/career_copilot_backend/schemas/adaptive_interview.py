from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from career_copilot_backend.schemas.analysis import AnalysisModel
from career_copilot_backend.schemas.rag import Citation

Skill = Annotated[str, Field(min_length=1, max_length=100)]
Seniority = Literal["junior", "mid", "senior"]
InterviewType = Literal["technical", "behavioral", "mixed"]


class AdaptiveInterviewCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    role: str = Field(min_length=1, max_length=200)
    seniority: Seniority
    interview_type: InterviewType = "technical"
    resume_id: UUID | None = None
    job_description: str | None = Field(default=None, max_length=20_000)
    skills: list[Skill] = Field(default_factory=list, max_length=20)

    @field_validator("role")
    @classmethod
    def normalize_role(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Role cannot be blank")
        return value

    @field_validator("job_description")
    @classmethod
    def normalize_description(cls, value: str | None) -> str | None:
        return value.strip() or None if value is not None else None

    @field_validator("skills")
    @classmethod
    def normalize_skills(cls, value: list[str]) -> list[str]:
        cleaned = [item.strip() for item in value]
        if any(not item for item in cleaned):
            raise ValueError("Skills cannot be blank")
        if len({item.casefold() for item in cleaned}) != len(cleaned):
            raise ValueError("Skills must be unique")
        return cleaned


class AdaptiveInterviewResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    resume_id: UUID | None
    role: str
    seniority: Seniority
    interview_type: InterviewType
    job_description: str | None
    skills: list[str]
    status: Literal["active", "completed"]
    state_version: int
    current_topic: str | None
    current_difficulty: int
    created_at: datetime
    updated_at: datetime
    completed_at: datetime | None


class AdaptiveInterviewPage(BaseModel):
    items: list[AdaptiveInterviewResponse]
    limit: int
    offset: int


class CoachingCriterion(AnalysisModel):
    score: int | None = Field(ge=0, le=4)
    explanation: str = Field(min_length=1, max_length=1000)


class AdaptiveEvaluation(AnalysisModel):
    rubric_version: str = Field(default="adaptive-evaluation-v1", max_length=64)
    classification: Literal[
        "correct", "partially_correct", "incorrect", "not_assessable"
    ]
    overall_score: int | None = Field(ge=0, le=4)
    correctness: CoachingCriterion
    completeness: CoachingCriterion
    reasoning: CoachingCriterion
    communication: CoachingCriterion
    demonstrated_concepts: list[Skill] = Field(max_length=8)
    missing_concepts: list[Skill] = Field(max_length=8)
    inaccuracies: list[str] = Field(max_length=8)
    evidence: list[str] = Field(max_length=8)
    reference_ids: list[str] = Field(default_factory=list, max_length=4)
    references: list[Citation] = Field(default_factory=list, max_length=4)
    reference_versions: dict[str, str] = Field(default_factory=dict, max_length=4)
    suggested_action: Literal["deepen", "clarify", "challenge", "new_topic"]
    feedback: str = Field(min_length=1, max_length=4000)
    example_answer: str | None = Field(default=None, min_length=1, max_length=1200)

    @model_validator(mode="after")
    def check_evidence(self) -> "AdaptiveEvaluation":
        has_score = self.overall_score is not None or any(
            item.score is not None
            for item in (
                self.correctness,
                self.completeness,
                self.reasoning,
                self.communication,
            )
        )
        if (has_score or self.demonstrated_concepts) and not self.evidence:
            raise ValueError("Scored evaluations require answer evidence")
        if self.classification == "not_assessable" and has_score:
            raise ValueError("Not-assessable answers cannot receive a score")
        if any(not item.strip() or len(item) > 1000 for item in self.evidence):
            raise ValueError("Evidence must be a bounded, nonblank excerpt")
        if len(self.reference_ids) != len(set(self.reference_ids)):
            raise ValueError("Duplicate references are not allowed")
        return self


class AdaptiveQuestion(AnalysisModel):
    prompt: str = Field(min_length=1, max_length=500)


class AdaptiveAnswer(BaseModel):
    model_config = ConfigDict(extra="forbid")
    answer: str = Field(min_length=1, max_length=4000)

    @field_validator("answer")
    @classmethod
    def answer_not_blank(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("Answer cannot be empty")
        return value


class AdaptiveTurnResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    session_id: UUID
    sequence: int
    topic: str
    difficulty: int
    question_type: str
    prompt: str
    prompt_version: str
    answer: str | None
    answer_revision: int
    evaluation: AdaptiveEvaluation | None
    created_at: datetime


class AdaptiveTurnPage(BaseModel):
    items: list[AdaptiveTurnResponse]
    limit: int
    offset: int


class AdaptiveJobRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    allow_provider_fallbacks: bool = False


class AdaptiveJobResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    session_id: UUID
    turn_id: UUID | None
    kind: Literal["next", "evaluation"]
    status: Literal["queued", "running", "completed", "failed"]
    error_code: str | None
    state_version: int
    answer_revision: int | None


class AdaptiveJobPage(BaseModel):
    items: list[AdaptiveJobResponse]
    limit: int
    offset: int


class TopicProgress(BaseModel):
    topic: str
    average_score: float
    evidence_count: int


class TopicProgressPage(BaseModel):
    items: list[TopicProgress]
    limit: int
    offset: int


class AdaptiveReport(BaseModel):
    session_id: UUID
    status: Literal["completed"]
    evaluated_answers: int
    average_score: float | None
    topic_progress: list[TopicProgress]
    missing_concepts: list[str]
    strongest_topics: list[str]
    study_topics: list[str]
    suggested_questions: list[str]
    previous_average_score: float | None = None
    score_change: float | None = None
    coaching_note: str = (
        "Scores are approximate practice feedback, not a measure of employability."
    )
