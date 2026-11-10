from typing import Annotated

from fastapi import APIRouter, Query

from career_copilot_backend.api.v1.routes.resumes import CurrentUser, Database
from career_copilot_backend.schemas.ai_usage import AIUsagePage
from career_copilot_backend.services.ai_usage import user_usage

router = APIRouter()


@router.get("", response_model=AIUsagePage)
def get_ai_usage(
    session: Database,
    user: CurrentUser,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> AIUsagePage:
    return user_usage(session, user.id, limit, offset)
