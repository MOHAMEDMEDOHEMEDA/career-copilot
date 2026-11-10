from uuid import UUID

from sqlalchemy import case, func, select
from sqlalchemy.orm import Session

from career_copilot_backend.models import AIUsage
from career_copilot_backend.schemas.ai_usage import (
    AIUsageItem,
    AIUsagePage,
    AIUsageSummary,
)


def user_usage(db: Session, user_id: UUID, limit: int, offset: int) -> AIUsagePage:
    row = db.execute(
        select(
            func.count(AIUsage.id),
            func.coalesce(func.sum(AIUsage.input_tokens), 0),
            func.coalesce(func.sum(AIUsage.output_tokens), 0),
            func.coalesce(func.sum(case((AIUsage.input_tokens.is_(None) | AIUsage.output_tokens.is_(None), 1), else_=0)), 0),
            func.coalesce(func.sum(AIUsage.cost_usd), 0),
            func.coalesce(func.sum(case((AIUsage.cost_usd.is_(None), 1), else_=0)), 0),
        ).where(AIUsage.user_id == user_id)
    ).one()
    items = db.scalars(
        select(AIUsage).where(AIUsage.user_id == user_id)
        .order_by(AIUsage.created_at.desc(), AIUsage.id.desc()).limit(limit).offset(offset)
    ).all()
    return AIUsagePage(
        summary=AIUsageSummary(attempts=row[0], known_input_tokens=row[1], known_output_tokens=row[2], attempts_with_unknown_tokens=row[3], known_cost_usd=float(row[4]), attempts_with_unknown_cost=row[5]),
        items=[AIUsageItem.model_validate(item) for item in items], limit=limit, offset=offset,
    )
