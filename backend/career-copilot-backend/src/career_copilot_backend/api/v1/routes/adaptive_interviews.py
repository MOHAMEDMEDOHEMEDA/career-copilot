from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, HTTPException, Query, Response
from sqlalchemy.orm import Session

from career_copilot_backend.api.v1.routes.resumes import CurrentUser, Database
from career_copilot_backend.core.config import settings
from career_copilot_backend.llm.alternatives import provider_configured
from career_copilot_backend.models import (
    AdaptiveInterviewSession,
    AdaptiveInterviewTurn,
    User,
)
from career_copilot_backend.schemas.adaptive_interview import (
    AdaptiveAnswer,
    AdaptiveInterviewCreate,
    AdaptiveInterviewPage,
    AdaptiveInterviewResponse,
    AdaptiveJobPage,
    AdaptiveJobRequest,
    AdaptiveJobResponse,
    AdaptiveReport,
    AdaptiveTurnPage,
    AdaptiveTurnResponse,
    TopicProgressPage,
)
from career_copilot_backend.services import adaptive_interviews
from career_copilot_backend.services.resumes import find_resume
from career_copilot_backend.services.usage import record_attempt

router = APIRouter()


def owned_session(
    db: Session, user: User, session_id: UUID, *, lock: bool = False
) -> AdaptiveInterviewSession:
    item = adaptive_interviews.find_session(db, user.id, session_id, lock=lock)
    if item is None:
        raise HTTPException(status_code=404, detail="Interview session not found")
    return item


@router.post("/sessions", response_model=AdaptiveInterviewResponse, status_code=201)
def create_session(
    body: AdaptiveInterviewCreate, session: Database, user: CurrentUser
) -> AdaptiveInterviewResponse:
    if (
        body.resume_id is not None
        and find_resume(session, user.id, body.resume_id) is None
    ):
        raise HTTPException(status_code=404, detail="Resume not found")
    return AdaptiveInterviewResponse.model_validate(
        adaptive_interviews.create_session(session, user.id, body)
    )


@router.get("/sessions", response_model=AdaptiveInterviewPage)
def list_sessions(
    session: Database,
    user: CurrentUser,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> AdaptiveInterviewPage:
    items = adaptive_interviews.list_sessions(session, user.id, limit, offset)
    return AdaptiveInterviewPage(
        items=[AdaptiveInterviewResponse.model_validate(item) for item in items],
        limit=limit,
        offset=offset,
    )


@router.get("/sessions/{session_id}", response_model=AdaptiveInterviewResponse)
def get_session(
    session_id: UUID, session: Database, user: CurrentUser
) -> AdaptiveInterviewResponse:
    return AdaptiveInterviewResponse.model_validate(
        owned_session(session, user, session_id)
    )


@router.delete("/sessions/{session_id}", status_code=204)
def delete_session(session_id: UUID, session: Database, user: CurrentUser) -> Response:
    adaptive_interviews.delete_session(
        session, owned_session(session, user, session_id, lock=True)
    )
    return Response(status_code=204)


@router.get("/sessions/{session_id}/turns", response_model=AdaptiveTurnPage)
def get_turns(
    session_id: UUID,
    session: Database,
    user: CurrentUser,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> AdaptiveTurnPage:
    owned_session(session, user, session_id)
    turns = adaptive_interviews.list_turns(session, session_id, limit, offset)
    return AdaptiveTurnPage(
        items=[AdaptiveTurnResponse.model_validate(turn) for turn in turns],
        limit=limit,
        offset=offset,
    )


@router.put(
    "/sessions/{session_id}/turns/{turn_id}/answer", response_model=AdaptiveTurnResponse
)
def save_answer(
    session_id: UUID,
    turn_id: UUID,
    body: AdaptiveAnswer,
    session: Database,
    user: CurrentUser,
) -> AdaptiveTurnResponse:
    interview = owned_session(session, user, session_id, lock=True)
    turn = adaptive_interviews.get_turn(session, session_id, turn_id)
    if turn is None:
        raise HTTPException(status_code=404, detail="Interview question not found")
    latest = adaptive_interviews.last_turn(session, session_id)
    if interview.status != "active" or latest is None or latest.id != turn.id:
        raise HTTPException(
            status_code=409, detail="Only the current question can be edited"
        )
    return AdaptiveTurnResponse.model_validate(
        adaptive_interviews.save_answer(session, interview, turn, body.answer)
    )


def queue_request(
    session_id: UUID,
    turn_id: UUID | None,
    body: AdaptiveJobRequest,
    session: Session,
    user: User,
) -> AdaptiveJobResponse:
    def validate() -> tuple[AdaptiveInterviewSession, AdaptiveInterviewTurn | None]:
        interview = owned_session(session, user, session_id, lock=True)
        if interview.status != "active":
            raise HTTPException(status_code=409, detail="Interview is not active")
        latest = adaptive_interviews.last_turn(session, session_id)
        if turn_id:
            turn = adaptive_interviews.get_turn(session, session_id, turn_id)
            if turn is None:
                raise HTTPException(
                    status_code=404, detail="Interview question not found"
                )
            if latest is None or turn.id != latest.id or not turn.answer:
                raise HTTPException(
                    status_code=409, detail="Answer the current question first"
                )
            return interview, turn
        if latest is not None and (not latest.answer or latest.evaluation is None):
            raise HTTPException(
                status_code=409, detail="Evaluate the current answer first"
            )
        if latest is not None and not adaptive_interviews.has_next_topic(
            interview, latest
        ):
            raise HTTPException(
                status_code=409, detail="No topics remain; complete the interview"
            )
        return interview, None

    interview, turn = validate()
    if existing := adaptive_interviews.existing_job(
        session, adaptive_interviews.job_key(interview, turn)
    ):
        return AdaptiveJobResponse.model_validate(existing)
    if not provider_configured(body.allow_provider_fallbacks):
        raise HTTPException(status_code=503, detail="AI provider is not configured")
    if not record_attempt(
        session,
        user.id,
        "adaptive_interview_ai",
        settings.adaptive_interview_limit_per_hour,
    ):
        raise HTTPException(
            status_code=429,
            detail="Interview AI limit exceeded",
            headers={"Retry-After": "3600"},
        )
    interview, turn = validate()
    return AdaptiveJobResponse.model_validate(
        adaptive_interviews.queue_job(
            session, interview, turn, body.allow_provider_fallbacks
        )
    )


@router.post(
    "/sessions/{session_id}/next", response_model=AdaptiveJobResponse, status_code=202
)
def request_next(
    session_id: UUID, body: AdaptiveJobRequest, session: Database, user: CurrentUser
) -> AdaptiveJobResponse:
    return queue_request(session_id, None, body, session, user)


@router.post(
    "/sessions/{session_id}/turns/{turn_id}/evaluation",
    response_model=AdaptiveJobResponse,
    status_code=202,
)
def request_evaluation(
    session_id: UUID,
    turn_id: UUID,
    body: AdaptiveJobRequest,
    session: Database,
    user: CurrentUser,
) -> AdaptiveJobResponse:
    return queue_request(session_id, turn_id, body, session, user)


@router.get("/sessions/{session_id}/jobs/{job_id}", response_model=AdaptiveJobResponse)
def get_job(
    session_id: UUID, job_id: UUID, session: Database, user: CurrentUser
) -> AdaptiveJobResponse:
    owned_session(session, user, session_id)
    job = adaptive_interviews.find_job(session, session_id, job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Interview job not found")
    return AdaptiveJobResponse.model_validate(job)


@router.get("/sessions/{session_id}/jobs", response_model=AdaptiveJobPage)
def get_jobs(
    session_id: UUID,
    session: Database,
    user: CurrentUser,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> AdaptiveJobPage:
    owned_session(session, user, session_id)
    jobs = adaptive_interviews.list_jobs(session, session_id, limit, offset)
    return AdaptiveJobPage(
        items=[AdaptiveJobResponse.model_validate(job) for job in jobs],
        limit=limit,
        offset=offset,
    )


@router.post(
    "/sessions/{session_id}/jobs/{job_id}/retry",
    response_model=AdaptiveJobResponse,
    status_code=202,
)
def retry_job(
    session_id: UUID,
    job_id: UUID,
    body: AdaptiveJobRequest,
    session: Database,
    user: CurrentUser,
) -> AdaptiveJobResponse:
    def validate():
        interview = owned_session(session, user, session_id, lock=True)
        job = adaptive_interviews.find_job(session, session_id, job_id, lock=True)
        if job is None:
            raise HTTPException(status_code=404, detail="Interview job not found")
        if (
            job.status != "failed"
            or interview.status != "active"
            or interview.state_version != job.state_version
        ):
            raise HTTPException(
                status_code=409,
                detail="Job cannot be retried for the current interview state",
            )
        if job.turn_id:
            turn = adaptive_interviews.get_turn(session, session_id, job.turn_id)
            if turn is None or turn.answer_revision != job.answer_revision:
                raise HTTPException(status_code=409, detail="Answer has changed")
        return job

    validate()
    if not provider_configured(body.allow_provider_fallbacks):
        raise HTTPException(status_code=503, detail="AI provider is not configured")
    if not record_attempt(
        session,
        user.id,
        "adaptive_interview_ai",
        settings.adaptive_interview_limit_per_hour,
    ):
        raise HTTPException(
            status_code=429,
            detail="Interview AI limit exceeded",
            headers={"Retry-After": "3600"},
        )
    job = validate()
    return AdaptiveJobResponse.model_validate(
        adaptive_interviews.retry_job(session, job, body.allow_provider_fallbacks)
    )


@router.post(
    "/sessions/{session_id}/complete", response_model=AdaptiveInterviewResponse
)
def complete_session(
    session_id: UUID, session: Database, user: CurrentUser
) -> AdaptiveInterviewResponse:
    interview = owned_session(session, user, session_id, lock=True)
    if interview.status == "completed":
        return AdaptiveInterviewResponse.model_validate(interview)
    turn = adaptive_interviews.last_turn(session, session_id)
    if turn is None or turn.evaluation is None:
        raise HTTPException(
            status_code=409,
            detail="Evaluate the current answer before completing the interview",
        )
    return AdaptiveInterviewResponse.model_validate(
        adaptive_interviews.complete_session(session, interview)
    )


@router.get("/sessions/{session_id}/report", response_model=AdaptiveReport)
def get_report(
    session_id: UUID, session: Database, user: CurrentUser
) -> AdaptiveReport:
    interview = owned_session(session, user, session_id)
    if interview.status != "completed":
        raise HTTPException(
            status_code=409, detail="Complete the interview to see the report"
        )
    return adaptive_interviews.make_report(session, interview)


@router.get("/skill-progress", response_model=TopicProgressPage)
def get_skill_progress(
    session: Database,
    user: CurrentUser,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> TopicProgressPage:
    return TopicProgressPage(
        items=adaptive_interviews.skill_progress(session, user.id, limit, offset),
        limit=limit,
        offset=offset,
    )
