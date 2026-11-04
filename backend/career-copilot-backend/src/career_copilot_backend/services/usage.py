from datetime import UTC, datetime, timedelta
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from career_copilot_backend.core.config import settings
from career_copilot_backend.models import UsageEvent, User


def record_upload_attempt(session: Session, user_id: UUID) -> bool:
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
                UsageEvent.operation == "resume_upload",
                UsageEvent.created_at >= since,
            )
        )
        or 0
    )
    if count >= settings.upload_limit_per_hour:
        session.rollback()
        return False
    session.add(UsageEvent(user_id=user_id, operation="resume_upload"))
    session.commit()
    return True
