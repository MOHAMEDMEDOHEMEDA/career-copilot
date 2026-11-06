from fastapi import APIRouter

from career_copilot_backend.api.v1.routes.analysis import router as analysis_router
from career_copilot_backend.api.v1.routes.auth import router as auth_router
from career_copilot_backend.api.v1.routes.health import router as health_router
from career_copilot_backend.api.v1.routes.job_matches import (
    router as job_matches_router,
)
from career_copilot_backend.api.v1.routes.jobs import router as jobs_router
from career_copilot_backend.api.v1.routes.resumes import router as resumes_router

api_router = APIRouter()
api_router.include_router(health_router, tags=["health"])
api_router.include_router(auth_router, prefix="/auth", tags=["auth"])
api_router.include_router(resumes_router, prefix="/resumes", tags=["resumes"])
api_router.include_router(jobs_router, prefix="/jobs", tags=["jobs"])
api_router.include_router(job_matches_router, prefix="/job-matches", tags=["job matching"])
api_router.include_router(
    analysis_router, prefix="/resume-analysis", tags=["resume analysis"]
)
