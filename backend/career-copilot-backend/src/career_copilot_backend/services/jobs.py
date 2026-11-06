from collections.abc import Callable, Mapping
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from sqlalchemy import select, update
from sqlalchemy.orm import Session, sessionmaker

from career_copilot_backend.llm.provider import ProviderError
from career_copilot_backend.models import Job, Resume
from career_copilot_backend.services.analysis import (
    AnalysisInputError,
    AnalysisOutputError,
)
from career_copilot_backend.services.job_match import UnsupportedEvidenceError


def create_job(session: Session, user_id: UUID, resume_id: UUID, kind: str, input_data: dict | None = None) -> Job:
    if (
        session.scalar(
            select(Resume.id).where(Resume.id == resume_id, Resume.user_id == user_id)
        )
        is None
    ):
        raise ValueError("Resume not found")
    job = Job(user_id=user_id, resume_id=resume_id, kind=kind, status="queued", input_data=input_data)
    session.add(job)
    session.commit()
    session.refresh(job)
    return job


def find_job(session: Session, user_id: UUID, job_id: UUID) -> Job | None:
    return session.scalar(select(Job).where(Job.id == job_id, Job.user_id == user_id))


def run_next_job(
    sessions: sessionmaker[Session],
    handlers: Mapping[str, Callable[[UUID], dict | None]],
    lease_seconds: int = 300,
) -> bool:
    if not handlers or lease_seconds <= 0:
        return False
    now = datetime.now(UTC)
    with sessions() as session:
        session.execute(
            update(Job)
            .where(Job.status == "running", Job.lease_expires_at < now)
            .values(status="failed", error_code="timeout", input_data=None, lease_id=None, lease_expires_at=None)
        )
        job = session.scalar(
            select(Job)
            .where(
                Job.kind.in_(handlers),
                Job.status == "queued",
            )
            .order_by(Job.created_at, Job.id)
            .with_for_update(skip_locked=True)
            .limit(1)
        )
        if job is None:
            session.commit()
            return False
        lease_id = uuid4()
        job.status = "running"
        job.lease_id = lease_id
        job.lease_expires_at = now + timedelta(seconds=lease_seconds)
        job.attempts += 1
        job_id, kind = job.id, job.kind
        session.commit()
    try:
        result = handlers[kind](job_id)
        status = "completed"
        error_code = None
    except Exception as exc:
        result = None
        status = "failed"
        if isinstance(exc, ProviderError):
            error_code = exc.code if exc.code in {"rate_limited", "provider_error", "provider_auth", "provider_unavailable", "output_limit", "timeout", "invalid_output"} else "provider_error"
        elif isinstance(exc, UnsupportedEvidenceError):
            error_code = "unsupported_evidence"
        elif isinstance(exc, AnalysisOutputError):
            error_code = "invalid_output"
        elif isinstance(exc, AnalysisInputError):
            error_code = "invalid_input"
        else:
            error_code = "timeout" if isinstance(exc, TimeoutError) else "analysis_failed"
    with sessions() as session:
        session.execute(
            update(Job)
            .where(Job.id == job_id, Job.lease_id == lease_id, Job.status == "running")
            .values(status=status, result=result, error_code=error_code, input_data=None, lease_id=None, lease_expires_at=None)
        )
        session.commit()
    return True
