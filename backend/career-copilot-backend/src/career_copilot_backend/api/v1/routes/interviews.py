from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, HTTPException, Query, Response
from sqlalchemy.orm import Session

from career_copilot_backend.api.v1.routes.resumes import CurrentUser, Database
from career_copilot_backend.core.config import settings
from career_copilot_backend.llm.alternatives import provider_configured
from career_copilot_backend.models import InterviewSession, User
from career_copilot_backend.schemas.interview import (
    InterviewAnswer,
    InterviewCreate,
    InterviewJobRequest,
    InterviewJobResponse,
    InterviewPage,
    InterviewResponse,
    QuestionPage,
    QuestionResponse,
)
from career_copilot_backend.services import interviews as interview_service
from career_copilot_backend.services.resumes import find_resume
from career_copilot_backend.services.usage import record_attempt

router = APIRouter()


def owned_session(
    db: Session, user: User, session_id: UUID, *, lock: bool = False
) -> InterviewSession:
    interview = interview_service.find_session(db, user.id, session_id, lock=lock)
    if interview is None:
        raise HTTPException(status_code=404, detail="Interview session not found")
    return interview


@router.post("/sessions", response_model=InterviewResponse, status_code=201)
def create_session(
    body: InterviewCreate, session: Database, user: CurrentUser
) -> InterviewResponse:
    if find_resume(session, user.id, body.resume_id) is None:
        raise HTTPException(status_code=404, detail="Resume not found")
    interview = interview_service.create_session(
        session, user.id, body.resume_id, body.job_description
    )
    return InterviewResponse.model_validate(interview)


@router.get("/sessions", response_model=InterviewPage)
def list_sessions(
    session: Database,
    user: CurrentUser,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> InterviewPage:
    items = interview_service.list_sessions(session, user.id, limit, offset)
    return InterviewPage(
        items=[InterviewResponse.model_validate(item) for item in items],
        limit=limit,
        offset=offset,
    )


@router.get("/sessions/{session_id}", response_model=InterviewResponse)
def get_session(
    session_id: UUID, session: Database, user: CurrentUser
) -> InterviewResponse:
    return InterviewResponse.model_validate(owned_session(session, user, session_id))


@router.delete("/sessions/{session_id}", status_code=204)
def remove_session(session_id: UUID, session: Database, user: CurrentUser) -> Response:
    interview = owned_session(session, user, session_id, lock=True)
    interview_service.delete_session(session, interview)
    return Response(status_code=204)


@router.get("/sessions/{session_id}/questions", response_model=QuestionPage)
def list_questions(
    session_id: UUID,
    session: Database,
    user: CurrentUser,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> QuestionPage:
    interview = owned_session(session, user, session_id)
    items = interview_service.list_questions(session, interview.id, limit, offset)
    return QuestionPage(
        items=[QuestionResponse.model_validate(item) for item in items],
        limit=limit,
        offset=offset,
    )


@router.put(
    "/sessions/{session_id}/questions/{question_id}/answer",
    response_model=QuestionResponse,
)
def save_answer(
    session_id: UUID,
    question_id: UUID,
    body: InterviewAnswer,
    session: Database,
    user: CurrentUser,
) -> QuestionResponse:
    interview = owned_session(session, user, session_id, lock=True)
    question = interview_service.save_answer(
        session, interview, question_id, body.answer
    )
    if question is None:
        raise HTTPException(status_code=404, detail="Interview question not found")
    return QuestionResponse.model_validate(question)


def queue_request(
    session_id: UUID,
    question_id: UUID | None,
    body: InterviewJobRequest,
    session: Session,
    user: User,
) -> InterviewJobResponse:
    interview = owned_session(session, user, session_id, lock=True)
    question = (
        interview_service.get_question(session, interview.id, question_id)
        if question_id
        else None
    )
    if question_id and question is None:
        raise HTTPException(status_code=404, detail="Interview question not found")
    if question is not None and not question.answer:
        raise HTTPException(status_code=409, detail="Answer the question first")
    existing = interview_service.existing_job(
        session, interview_service.job_key(interview, question)
    )
    if existing:
        return InterviewJobResponse.model_validate(existing)
    if not provider_configured(body.allow_provider_fallbacks):
        raise HTTPException(status_code=503, detail="AI provider is not configured")
    if not record_attempt(
        session, user.id, "interview_ai", settings.analysis_limit_per_hour
    ):
        raise HTTPException(
            status_code=429,
            detail="Interview AI limit exceeded",
            headers={"Retry-After": "3600"},
        )
    interview = owned_session(session, user, session_id, lock=True)
    question = (
        interview_service.get_question(session, interview.id, question_id)
        if question_id
        else None
    )
    if question_id and question is None:
        raise HTTPException(status_code=404, detail="Interview question not found")
    if question is not None and not question.answer:
        raise HTTPException(status_code=409, detail="Answer the question first")
    return InterviewJobResponse.model_validate(
        interview_service.queue_job(
            session, interview, question, body.allow_provider_fallbacks
        )
    )


@router.post(
    "/sessions/{session_id}/generation",
    response_model=InterviewJobResponse,
    status_code=202,
)
def request_questions(
    session_id: UUID, body: InterviewJobRequest, session: Database, user: CurrentUser
) -> InterviewJobResponse:
    return queue_request(session_id, None, body, session, user)


@router.post(
    "/sessions/{session_id}/questions/{question_id}/feedback",
    response_model=InterviewJobResponse,
    status_code=202,
)
def request_feedback(
    session_id: UUID,
    question_id: UUID,
    body: InterviewJobRequest,
    session: Database,
    user: CurrentUser,
) -> InterviewJobResponse:
    return queue_request(session_id, question_id, body, session, user)


@router.get("/sessions/{session_id}/jobs/{job_id}", response_model=InterviewJobResponse)
def job_status(
    session_id: UUID, job_id: UUID, session: Database, user: CurrentUser
) -> InterviewJobResponse:
    owned_session(session, user, session_id)
    job = interview_service.find_job(session, session_id, job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Interview job not found")
    return InterviewJobResponse.model_validate(job)


@router.post(
    "/sessions/{session_id}/jobs/{job_id}/retry",
    response_model=InterviewJobResponse,
    status_code=202,
)
def retry_job(
    session_id: UUID,
    job_id: UUID,
    body: InterviewJobRequest,
    session: Database,
    user: CurrentUser,
) -> InterviewJobResponse:
    owned_session(session, user, session_id, lock=True)
    job = interview_service.find_job(session, session_id, job_id, lock=True)
    if job is None:
        raise HTTPException(status_code=404, detail="Interview job not found")
    if job.status != "failed":
        raise HTTPException(status_code=409, detail="Only failed jobs can be retried")
    if job.question_id:
        question = interview_service.get_question(session, session_id, job.question_id)
        if question is None or question.answer_revision != job.answer_revision:
            raise HTTPException(
                status_code=409, detail="Answer has changed; request new feedback"
            )
    if not provider_configured(body.allow_provider_fallbacks):
        raise HTTPException(status_code=503, detail="AI provider is not configured")
    if not record_attempt(
        session, user.id, "interview_ai", settings.analysis_limit_per_hour
    ):
        raise HTTPException(
            status_code=429,
            detail="Interview AI limit exceeded",
            headers={"Retry-After": "3600"},
        )
    owned_session(session, user, session_id, lock=True)
    job = interview_service.find_job(session, session_id, job_id, lock=True)
    if job is None:
        raise HTTPException(status_code=404, detail="Interview job not found")
    if job.status != "failed":
        raise HTTPException(status_code=409, detail="Only failed jobs can be retried")
    if job.question_id:
        question = interview_service.get_question(session, session_id, job.question_id)
        if question is None or question.answer_revision != job.answer_revision:
            raise HTTPException(
                status_code=409, detail="Answer has changed; request new feedback"
            )
    return InterviewJobResponse.model_validate(
        interview_service.retry_job(session, job, body.allow_provider_fallbacks)
    )
