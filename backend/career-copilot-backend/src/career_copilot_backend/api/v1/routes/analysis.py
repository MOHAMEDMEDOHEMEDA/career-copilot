from uuid import UUID

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from career_copilot_backend.api.v1.routes.resumes import CurrentUser, Database
from career_copilot_backend.core.config import settings
from career_copilot_backend.schemas.job import JobResponse
from career_copilot_backend.services.analysis import MAX_RESUME_CHARACTERS
from career_copilot_backend.services.jobs import create_job
from career_copilot_backend.services.resumes import find_resume
from career_copilot_backend.services.usage import record_attempt

router = APIRouter()


class AnalysisRequest(BaseModel):
    resume_id: UUID


@router.post("", response_model=JobResponse, status_code=202)
def queue_analysis(
    body: AnalysisRequest, session: Database, user: CurrentUser
) -> JobResponse:
    resume = find_resume(session, user.id, body.resume_id)
    if resume is None:
        raise HTTPException(status_code=404, detail="Resume not found")
    if not resume.text.strip() or len(resume.text) > MAX_RESUME_CHARACTERS:
        raise HTTPException(status_code=422, detail="Resume exceeds analysis limits")
    if not settings.openrouter_api_key.get_secret_value().strip():
        raise HTTPException(
            status_code=503, detail="Analysis provider is not configured"
        )
    if not record_attempt(
        session, user.id, "resume_analysis", settings.analysis_limit_per_hour
    ):
        raise HTTPException(
            status_code=429,
            detail="Analysis limit exceeded",
            headers={"Retry-After": "3600"},
        )
    return JobResponse.model_validate(
        create_job(session, user.id, body.resume_id, "resume_analysis")
    )
