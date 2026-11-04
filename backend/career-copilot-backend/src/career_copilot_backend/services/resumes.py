from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from career_copilot_backend.models import Resume


def find_resume(session: Session, user_id: UUID, resume_id: UUID) -> Resume | None:
    return session.scalar(
        select(Resume).where(Resume.id == resume_id, Resume.user_id == user_id)
    )


def list_resumes(
    session: Session, user_id: UUID, limit: int, offset: int
) -> list[Resume]:
    return list(
        session.scalars(
            select(Resume)
            .where(Resume.user_id == user_id)
            .order_by(Resume.created_at, Resume.id)
            .offset(offset)
            .limit(limit)
        )
    )


def save_resume(session: Session, user_id: UUID, filename: str, text: str) -> Resume:
    resume = Resume(user_id=user_id, filename=filename, text=text)
    session.add(resume)
    session.commit()
    session.refresh(resume)
    return resume
