from uuid import UUID

from fastapi import APIRouter, HTTPException

from career_copilot_backend.api.v1.routes.resumes import CurrentUser, Database
from career_copilot_backend.schemas.job import JobResponse
from career_copilot_backend.services.jobs import find_job

router = APIRouter()


@router.get("/{job_id}", response_model=JobResponse)
def get_job(job_id: UUID, session: Database, user: CurrentUser) -> JobResponse:
    job = find_job(session, user.id, job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Job not found")
    return JobResponse.model_validate(job)
