from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from career_copilot_backend.models import (
    InterviewJob,
    InterviewQuestion,
    InterviewSession,
)


def find_session(
    db: Session, user_id: UUID, session_id: UUID, *, lock: bool = False
) -> InterviewSession | None:
    query = select(InterviewSession).where(
        InterviewSession.id == session_id, InterviewSession.user_id == user_id
    )
    return db.scalar(query.with_for_update() if lock else query)


def create_session(
    db: Session, user_id: UUID, resume_id: UUID, job_description: str
) -> InterviewSession:
    interview = InterviewSession(
        user_id=user_id, resume_id=resume_id, job_description=job_description
    )
    db.add(interview)
    db.commit()
    db.refresh(interview)
    return interview


def list_sessions(
    db: Session, user_id: UUID, limit: int, offset: int
) -> list[InterviewSession]:
    return list(
        db.scalars(
            select(InterviewSession)
            .where(InterviewSession.user_id == user_id)
            .order_by(InterviewSession.created_at.desc(), InterviewSession.id.desc())
            .offset(offset)
            .limit(limit)
        )
    )


def delete_session(db: Session, interview: InterviewSession) -> None:
    db.execute(delete(InterviewJob).where(InterviewJob.session_id == interview.id))
    db.execute(
        delete(InterviewQuestion).where(InterviewQuestion.session_id == interview.id)
    )
    db.delete(interview)
    db.commit()


def list_questions(
    db: Session, session_id: UUID, limit: int, offset: int
) -> list[InterviewQuestion]:
    return list(
        db.scalars(
            select(InterviewQuestion)
            .where(InterviewQuestion.session_id == session_id)
            .order_by(InterviewQuestion.sequence)
            .offset(offset)
            .limit(limit)
        )
    )


def save_answer(
    db: Session, interview: InterviewSession, question_id: UUID, answer: str
) -> InterviewQuestion | None:
    question = db.scalar(
        select(InterviewQuestion)
        .where(
            InterviewQuestion.id == question_id,
            InterviewQuestion.session_id == interview.id,
        )
        .with_for_update()
    )
    if question is None:
        return None
    if question.answer != answer:
        question.answer = answer
        question.answer_revision += 1
        question.feedback = None
        interview.updated_at = datetime.now(UTC)
    db.commit()
    db.refresh(question)
    return question


def get_question(
    db: Session, session_id: UUID, question_id: UUID
) -> InterviewQuestion | None:
    return db.scalar(
        select(InterviewQuestion).where(
            InterviewQuestion.session_id == session_id,
            InterviewQuestion.id == question_id,
        )
    )


def find_job(
    db: Session, session_id: UUID, job_id: UUID, *, lock: bool = False
) -> InterviewJob | None:
    query = select(InterviewJob).where(
        InterviewJob.session_id == session_id, InterviewJob.id == job_id
    )
    return db.scalar(
        query.with_for_update().execution_options(populate_existing=True)
        if lock
        else query
    )


def job_key(interview: InterviewSession, question: InterviewQuestion | None) -> str:
    return (
        f"feedback:{question.id}:{question.answer_revision}"
        if question
        else f"generation:{interview.id}"
    )


def existing_job(db: Session, key: str) -> InterviewJob | None:
    return db.scalar(select(InterviewJob).where(InterviewJob.dedup_key == key))


def queue_job(
    db: Session,
    interview: InterviewSession,
    question: InterviewQuestion | None,
    allow_fallbacks: bool,
) -> InterviewJob:
    key = job_key(interview, question)
    job = existing_job(db, key)
    if job is not None:
        return job
    job = InterviewJob(
        session_id=interview.id,
        question_id=question.id if question else None,
        dedup_key=key,
        kind="feedback" if question else "generation",
        answer_revision=question.answer_revision if question else None,
        allow_provider_fallbacks=allow_fallbacks,
    )
    db.add(job)
    db.commit()
    db.refresh(job)
    return job


def retry_job(db: Session, job: InterviewJob, allow_fallbacks: bool) -> InterviewJob:
    job.status = "queued"
    job.error_code = None
    job.allow_provider_fallbacks = allow_fallbacks
    db.commit()
    db.refresh(job)
    return job
