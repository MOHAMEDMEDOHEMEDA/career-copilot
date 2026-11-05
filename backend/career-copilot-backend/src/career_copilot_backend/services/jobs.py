from collections.abc import Callable, Mapping
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from sqlalchemy import select, update
from sqlalchemy.orm import Session, sessionmaker

from career_copilot_backend.models import Job, Resume


def create_job(session: Session, user_id: UUID, resume_id: UUID, kind: str) -> Job:
    if (
        session.scalar(
            select(Resume.id).where(Resume.id == resume_id, Resume.user_id == user_id)
        )
        is None
    ):
        raise ValueError("Resume not found")
    job = Job(user_id=user_id, resume_id=resume_id, kind=kind, status="queued")
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
            .values(status="failed", lease_id=None, lease_expires_at=None)
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
    except Exception:
        result = None
        status = "failed"
    with sessions() as session:
        session.execute(
            update(Job)
            .where(Job.id == job_id, Job.lease_id == lease_id, Job.status == "running")
            .values(status=status, result=result, lease_id=None, lease_expires_at=None)
        )
        session.commit()
    return True
