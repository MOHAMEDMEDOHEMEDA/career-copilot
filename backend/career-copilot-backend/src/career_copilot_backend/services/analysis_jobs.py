import asyncio
import time
from uuid import UUID

from sqlalchemy.orm import Session, sessionmaker

from career_copilot_backend.core.database import SessionLocal
from career_copilot_backend.llm.alternatives import (
    FallbackProvider,
    configured_provider,
)
from career_copilot_backend.llm.provider import LLMProvider
from career_copilot_backend.models import Job, Resume
from career_copilot_backend.services.analysis import analyze_resume
from career_copilot_backend.services.job_match import match_job
from career_copilot_backend.services.jobs import run_next_job


def process_analysis(
    sessions: sessionmaker[Session], provider: LLMProvider, job_id: UUID
) -> dict:
    with sessions() as session:
        job = session.get(Job, job_id)
        if job is None:
            raise ValueError("Job not found")
        resume = session.get(Resume, job.resume_id)
        if resume is None or resume.user_id != job.user_id:
            raise ValueError("Resume not found")
        text = resume.text
        allow_fallbacks = bool((job.input_data or {}).get("allow_provider_fallbacks", False))
    if isinstance(provider, FallbackProvider):
        provider = provider.for_consent(allow_fallbacks)
    return asyncio.run(analyze_resume(provider, text)).model_dump()


def process_job_match(sessions: sessionmaker[Session], provider: LLMProvider, job_id: UUID) -> dict:
    with sessions() as session:
        job = session.get(Job, job_id)
        if job is None or not job.input_data:
            raise ValueError("Job input not found")
        resume = session.get(Resume, job.resume_id)
        if resume is None or resume.user_id != job.user_id:
            raise ValueError("Resume not found")
        text = resume.text
        description = job.input_data["job_description"]
        allow_fallbacks = bool(job.input_data.get("allow_provider_fallbacks", False))
    if isinstance(provider, FallbackProvider):
        provider = provider.for_consent(allow_fallbacks)
    return asyncio.run(match_job(provider, text, description)).model_dump()


def main() -> None:
    provider = configured_provider()
    while True:
        processed = run_next_job(
            SessionLocal,
            {
                "resume_analysis": lambda job_id: process_analysis(
                    SessionLocal, provider, job_id
                ),
                "job_match": lambda job_id: process_job_match(SessionLocal, provider, job_id),
            },
        )
        if not processed:
            time.sleep(2)


if __name__ == "__main__":
    main()
