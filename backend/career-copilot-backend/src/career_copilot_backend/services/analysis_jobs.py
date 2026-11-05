import asyncio
import time
from uuid import UUID

from sqlalchemy.orm import Session, sessionmaker

from career_copilot_backend.core.database import SessionLocal
from career_copilot_backend.llm.openrouter import configured_openrouter
from career_copilot_backend.llm.provider import LLMProvider
from career_copilot_backend.models import Job, Resume
from career_copilot_backend.services.analysis import analyze_resume
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
    return asyncio.run(analyze_resume(provider, text)).model_dump()


def main() -> None:
    provider = configured_openrouter()
    while True:
        processed = run_next_job(
            SessionLocal,
            {
                "resume_analysis": lambda job_id: process_analysis(
                    SessionLocal, provider, job_id
                )
            },
        )
        if not processed:
            time.sleep(2)


if __name__ == "__main__":
    main()
