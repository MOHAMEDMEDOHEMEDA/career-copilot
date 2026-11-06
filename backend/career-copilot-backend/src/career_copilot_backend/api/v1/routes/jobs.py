from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, HTTPException, Query
from sqlalchemy import select

from career_copilot_backend.api.v1.routes.resumes import CurrentUser, Database
from career_copilot_backend.models import Job
from career_copilot_backend.schemas.job import JobPage, JobResponse
from career_copilot_backend.services.jobs import find_job
from career_copilot_backend.services.resumes import find_resume

router = APIRouter()


@router.get("", response_model=JobPage)
def list_analysis_jobs(
    resume_id: UUID, session: Database, user: CurrentUser,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> JobPage:
    if find_resume(session, user.id, resume_id) is None:
        raise HTTPException(status_code=404, detail="Resume not found")
    jobs = session.scalars(select(Job).where(
        Job.user_id == user.id, Job.resume_id == resume_id, Job.kind == "resume_analysis"
    ).order_by(Job.created_at.desc(), Job.id.desc()).offset(offset).limit(limit)).all()
    return JobPage(items=[JobResponse.model_validate(job) for job in jobs], limit=limit, offset=offset)


@router.get("/{job_id}", response_model=JobResponse)
def get_job(job_id: UUID, session: Database, user: CurrentUser) -> JobResponse:
    job = find_job(session, user.id, job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Job not found")
    return JobResponse.model_validate(job)
