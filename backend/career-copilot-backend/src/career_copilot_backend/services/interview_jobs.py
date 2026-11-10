import asyncio
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from sqlalchemy import select, update
from sqlalchemy.orm import Session, sessionmaker

from career_copilot_backend.llm.alternatives import FallbackProvider
from career_copilot_backend.llm.provider import LLMProvider, ProviderError
from career_copilot_backend.llm.usage import capture_usage
from career_copilot_backend.models import (
    InterviewJob,
    InterviewQuestion,
    InterviewSession,
    Resume,
)
from career_copilot_backend.schemas.interview import (
    InterviewFeedback,
    InterviewQuestions,
)
from career_copilot_backend.services.analysis import (
    AnalysisInputError,
    AnalysisOutputError,
)
from career_copilot_backend.services.interview_ai import (
    evaluate_answer,
    generate_questions,
)


def process_interview_job(
    sessions: sessionmaker[Session], provider: LLMProvider, job_id: UUID
) -> InterviewQuestions | InterviewFeedback:
    with sessions() as db:
        job = db.get(InterviewJob, job_id)
        if job is None:
            raise AnalysisInputError("Job not found")
        interview = db.get(InterviewSession, job.session_id)
        if interview is None:
            raise AnalysisInputError("Session not found")
        resume = db.get(Resume, interview.resume_id)
        if resume is None or resume.user_id != interview.user_id:
            raise AnalysisInputError("Resume not found")
        if isinstance(provider, FallbackProvider):
            provider = provider.for_consent(job.allow_provider_fallbacks)
        if job.kind == "generation":
            return asyncio.run(
                generate_questions(provider, resume.text, interview.job_description)
            )
        question = db.get(InterviewQuestion, job.question_id)
        if (
            question is None
            or question.session_id != interview.id
            or not question.answer
            or question.answer_revision != job.answer_revision
        ):
            raise AnalysisInputError("Answer is no longer current")
        return asyncio.run(
            evaluate_answer(
                provider,
                resume.text,
                interview.job_description,
                question.prompt,
                question.answer,
            )
        )


def run_next_interview_job(
    sessions: sessionmaker[Session],
    handler: Callable[[UUID], InterviewQuestions | InterviewFeedback],
    lease_seconds: int = 300,
) -> bool:
    now = datetime.now(UTC)
    with sessions() as db:
        db.execute(
            update(InterviewJob)
            .where(
                InterviewJob.status == "running", InterviewJob.lease_expires_at < now
            )
            .values(
                status="failed",
                error_code="timeout",
                lease_id=None,
                lease_expires_at=None,
            )
        )
        job = db.scalar(
            select(InterviewJob)
            .where(InterviewJob.status == "queued")
            .order_by(InterviewJob.created_at, InterviewJob.id)
            .with_for_update(skip_locked=True)
            .limit(1)
        )
        if job is None:
            db.commit()
            return False
        lease = uuid4()
        job.status = "running"
        job.lease_id = lease
        job.lease_expires_at = now + timedelta(seconds=lease_seconds)
        job.attempts += 1
        job_id = job.id
        interview = db.get(InterviewSession, job.session_id)
        user_id = interview.user_id if interview else None
        operation = f"interview_{job.kind}"
        db.commit()
    try:
        with capture_usage(sessions, user_id, operation, job_id):
            result = handler(job_id)
        error = None
    except Exception as exc:  # noqa: BLE001 - never persist provider or user content in errors
        result = None
        if isinstance(exc, ProviderError):
            error = (
                exc.code
                if exc.code
                in {
                    "rate_limited",
                    "provider_error",
                    "provider_auth",
                    "provider_unavailable",
                    "output_limit",
                    "timeout",
                    "invalid_output",
                }
                else "provider_error"
            )
        elif isinstance(exc, AnalysisOutputError):
            error = "invalid_output"
        elif isinstance(exc, AnalysisInputError):
            error = "invalid_input"
        else:
            error = "timeout" if isinstance(exc, TimeoutError) else "analysis_failed"
    with sessions() as db:
        snapshot = db.get(InterviewJob, job_id)
        if snapshot is None:
            return True
        interview = db.scalar(
            select(InterviewSession)
            .where(InterviewSession.id == snapshot.session_id)
            .with_for_update()
        )
        if interview is None:
            return True
        job = db.scalar(
            select(InterviewJob)
            .where(
                InterviewJob.id == job_id,
                InterviewJob.lease_id == lease,
                InterviewJob.status == "running",
            )
            .with_for_update()
            .execution_options(populate_existing=True)
        )
        if job is None:
            return True
        if (
            isinstance(result, InterviewQuestions)
            and job.kind == "generation"
            and interview.status == "draft"
        ):
            for number, item in enumerate(result.questions, start=1):
                db.add(
                    InterviewQuestion(
                        session_id=interview.id, sequence=number, prompt=item.prompt
                    )
                )
            interview.status = "ready"
            job.status = "completed"
        elif isinstance(result, InterviewFeedback) and job.kind == "feedback":
            question = db.scalar(
                select(InterviewQuestion)
                .where(
                    InterviewQuestion.id == job.question_id,
                    InterviewQuestion.session_id == interview.id,
                )
                .with_for_update()
            )
            if question is not None and question.answer_revision == job.answer_revision:
                question.feedback = result.model_dump()
                job.status = "completed"
            else:
                job.status = "failed"
                job.error_code = "stale_answer"
        else:
            job.status = "failed"
            job.error_code = error or "invalid_output"
        job.lease_id = None
        job.lease_expires_at = None
        db.commit()
    return True
