from uuid import UUID

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from career_copilot_backend.api.v1.routes.resumes import CurrentUser, Database
from career_copilot_backend.core.config import settings
from career_copilot_backend.llm.alternatives import provider_configured
from career_copilot_backend.schemas.job import JobResponse
from career_copilot_backend.services.analysis import MAX_RESUME_CHARACTERS
from career_copilot_backend.services.job_match import MAX_JOB_DESCRIPTION_CHARACTERS
from career_copilot_backend.services.jobs import create_job
from career_copilot_backend.services.resumes import find_resume
from career_copilot_backend.services.usage import record_attempt

router = APIRouter()


class JobMatchRequest(BaseModel):
    resume_id: UUID
    job_description: str = Field(min_length=1, max_length=MAX_JOB_DESCRIPTION_CHARACTERS)
    allow_provider_fallbacks: bool = False


@router.post("", response_model=JobResponse, status_code=202)
def queue_match(body: JobMatchRequest, session: Database, user: CurrentUser) -> JobResponse:
    resume = find_resume(session, user.id, body.resume_id)
    if resume is None:
        raise HTTPException(status_code=404, detail="Resume not found")
    if not resume.text.strip() or len(resume.text) > MAX_RESUME_CHARACTERS or not body.job_description.strip():
        raise HTTPException(status_code=422, detail="Resume or job description exceeds matching limits")
    if not provider_configured(body.allow_provider_fallbacks):
        raise HTTPException(status_code=503, detail="Analysis provider is not configured")
    if not record_attempt(session, user.id, "job_match", settings.analysis_limit_per_hour):
        raise HTTPException(status_code=429, detail="Job matching limit exceeded", headers={"Retry-After": "3600"})
    job = create_job(session, user.id, body.resume_id, "job_match", {"job_description": body.job_description, "allow_provider_fallbacks": body.allow_provider_fallbacks})
    return JobResponse.model_validate(job)
