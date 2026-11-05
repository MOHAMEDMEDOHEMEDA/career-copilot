from datetime import UTC, datetime, timedelta
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from career_copilot_backend.core.config import settings
from career_copilot_backend.models import UsageEvent, User


def record_upload_attempt(session: Session, user_id: UUID) -> bool:
    return record_attempt(
        session, user_id, "resume_upload", settings.upload_limit_per_hour
    )


def record_attempt(session: Session, user_id: UUID, operation: str, limit: int) -> bool:
    session.execute(
        select(User.id).where(User.id == user_id).with_for_update()
    ).scalar_one()
    since = datetime.now(UTC) - timedelta(hours=1)
    count = (
        session.scalar(
            select(func.count())
            .select_from(UsageEvent)
            .where(
                UsageEvent.user_id == user_id,
                UsageEvent.operation == operation,
                UsageEvent.created_at >= since,
            )
        )
        or 0
    )
    if count >= limit:
        session.rollback()
        return False
    session.add(UsageEvent(user_id=user_id, operation=operation))
    session.commit()
    return True
