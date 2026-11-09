from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import JSON, DateTime, ForeignKey, String, Text, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from career_copilot_backend.core.database import Base


class AdaptiveInterviewSession(Base):
    __tablename__ = "adaptive_interview_sessions"

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    resume_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("resumes.id", ondelete="CASCADE"), nullable=True
    )
    role: Mapped[str] = mapped_column(String(200), nullable=False)
    seniority: Mapped[str] = mapped_column(String(16), nullable=False)
    interview_type: Mapped[str] = mapped_column(String(16), nullable=False)
    job_description: Mapped[str | None] = mapped_column(Text, nullable=True)
    skills: Mapped[list[str]] = mapped_column(JSON, nullable=False, default=list)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="active")
    state_version: Mapped[int] = mapped_column(nullable=False, default=0)
    current_topic: Mapped[str | None] = mapped_column(String(200), nullable=True)
    current_difficulty: Mapped[int] = mapped_column(nullable=False, default=1)
    topics: Mapped[list] = mapped_column(JSON, nullable=False, default=list)
    covered_topics: Mapped[list] = mapped_column(JSON, nullable=False, default=list)
    follow_up_count: Mapped[int] = mapped_column(nullable=False, default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )
    completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )


class AdaptiveInterviewTurn(Base):
    __tablename__ = "adaptive_interview_turns"
    __table_args__ = (UniqueConstraint("session_id", "sequence"),)

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    session_id: Mapped[UUID] = mapped_column(
        ForeignKey("adaptive_interview_sessions.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    sequence: Mapped[int] = mapped_column(nullable=False)
    topic: Mapped[str] = mapped_column(String(200), nullable=False)
    difficulty: Mapped[int] = mapped_column(nullable=False)
    question_type: Mapped[str] = mapped_column(String(32), nullable=False)
    prompt: Mapped[str] = mapped_column(Text, nullable=False)
    prompt_version: Mapped[str] = mapped_column(
        String(64), nullable=False, default="adaptive-question-v1"
    )
    answer: Mapped[str | None] = mapped_column(Text, nullable=True)
    answer_revision: Mapped[int] = mapped_column(nullable=False, default=0)
    evaluation: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
