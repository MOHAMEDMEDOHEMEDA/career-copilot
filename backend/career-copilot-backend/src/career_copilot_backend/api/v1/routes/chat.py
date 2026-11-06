from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, HTTPException, Query, Response
from sqlalchemy import select
from sqlalchemy.orm import Session

from career_copilot_backend.api.v1.routes.resumes import CurrentUser, Database
from career_copilot_backend.core.config import settings
from career_copilot_backend.llm.alternatives import provider_configured
from career_copilot_backend.models import ChatAnswerJob, ChatMessage, Conversation, User
from career_copilot_backend.schemas.chat import (
    AnswerJobResponse,
    AnswerRequest,
    AnswerRetry,
    ConversationCreate,
    ConversationPage,
    ConversationResponse,
    MessageCreate,
    MessagePage,
    MessageResponse,
)
from career_copilot_backend.services.chat import (
    add_user_message,
    create_conversation,
    delete_conversation,
    find_conversation,
    list_conversations,
    list_messages,
)
from career_copilot_backend.services.chat_answers import get_answer_job, queue_answer
from career_copilot_backend.services.usage import record_attempt

router = APIRouter()


def owned_conversation(
    session: Session, user: User, conversation_id: UUID, *, lock: bool = False
) -> Conversation:
    conversation = find_conversation(session, user.id, conversation_id, lock=lock)
    if conversation is None:
        raise HTTPException(status_code=404, detail="Conversation not found")
    return conversation


@router.post("/conversations", response_model=ConversationResponse, status_code=201)
def new_conversation(
    body: ConversationCreate, session: Database, user: CurrentUser
) -> ConversationResponse:
    return ConversationResponse.model_validate(
        create_conversation(session, user.id, body.title)
    )


@router.get("/conversations", response_model=ConversationPage)
def get_conversations(
    session: Database,
    user: CurrentUser,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> ConversationPage:
    return ConversationPage(
        items=[
            ConversationResponse.model_validate(item)
            for item in list_conversations(session, user.id, limit, offset)
        ],
        limit=limit,
        offset=offset,
    )


@router.get("/conversations/{conversation_id}", response_model=ConversationResponse)
def get_conversation(
    conversation_id: UUID, session: Database, user: CurrentUser
) -> ConversationResponse:
    return ConversationResponse.model_validate(
        owned_conversation(session, user, conversation_id)
    )


@router.delete("/conversations/{conversation_id}", status_code=204)
def remove_conversation(
    conversation_id: UUID, session: Database, user: CurrentUser
) -> Response:
    delete_conversation(
        session, owned_conversation(session, user, conversation_id, lock=True)
    )
    return Response(status_code=204)


@router.post(
    "/conversations/{conversation_id}/messages",
    response_model=MessageResponse,
    status_code=201,
)
def post_message(
    conversation_id: UUID, body: MessageCreate, session: Database, user: CurrentUser
) -> MessageResponse:
    conversation = owned_conversation(session, user, conversation_id, lock=True)
    return MessageResponse.model_validate(
        add_user_message(session, conversation, body.content)
    )


@router.get("/conversations/{conversation_id}/messages", response_model=MessagePage)
def get_messages(
    conversation_id: UUID,
    session: Database,
    user: CurrentUser,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> MessagePage:
    conversation = owned_conversation(session, user, conversation_id)
    return MessagePage(
        items=[
            MessageResponse.model_validate(item)
            for item in list_messages(session, conversation.id, limit, offset)
        ],
        limit=limit,
        offset=offset,
    )


@router.post(
    "/conversations/{conversation_id}/answers",
    response_model=AnswerJobResponse,
    status_code=202,
)
def request_answer(
    conversation_id: UUID, body: AnswerRequest, session: Database, user: CurrentUser
) -> AnswerJobResponse:
    conversation = owned_conversation(session, user, conversation_id, lock=True)
    question = session.scalar(
        select(ChatMessage.id).where(
            ChatMessage.id == body.message_id,
            ChatMessage.conversation_id == conversation.id,
            ChatMessage.role == "user",
        )
    )
    if question is None:
        raise HTTPException(status_code=404, detail="Message not found")
    existing = session.scalar(
        select(ChatAnswerJob).where(ChatAnswerJob.question_id == body.message_id)
    )
    if existing:
        return AnswerJobResponse.model_validate(existing)
    if not provider_configured(body.allow_provider_fallbacks):
        raise HTTPException(status_code=503, detail="AI provider is not configured")
    if not record_attempt(
        session, user.id, "chat_answer", settings.analysis_limit_per_hour
    ):
        raise HTTPException(
            status_code=429,
            detail="Chat answer limit exceeded",
            headers={"Retry-After": "3600"},
        )
    conversation = owned_conversation(session, user, conversation_id, lock=True)
    job = queue_answer(
        session, conversation, body.message_id, body.allow_provider_fallbacks
    )
    if job is None:
        raise HTTPException(status_code=404, detail="Message not found")
    return AnswerJobResponse.model_validate(job)


@router.get(
    "/conversations/{conversation_id}/answers/{job_id}",
    response_model=AnswerJobResponse,
)
def answer_status(
    conversation_id: UUID, job_id: UUID, session: Database, user: CurrentUser
) -> AnswerJobResponse:
    owned_conversation(session, user, conversation_id)
    job = get_answer_job(session, conversation_id, job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Answer job not found")
    return AnswerJobResponse.model_validate(job)


@router.post(
    "/conversations/{conversation_id}/answers/{job_id}/retry",
    response_model=AnswerJobResponse,
    status_code=202,
)
def retry_answer(
    conversation_id: UUID,
    job_id: UUID,
    body: AnswerRetry,
    session: Database,
    user: CurrentUser,
) -> AnswerJobResponse:
    owned_conversation(session, user, conversation_id, lock=True)
    job = get_answer_job(session, conversation_id, job_id, lock=True)
    if job is None:
        raise HTTPException(status_code=404, detail="Answer job not found")
    if job.status != "failed":
        raise HTTPException(status_code=409, detail="Only failed jobs can be retried")
    if not provider_configured(body.allow_provider_fallbacks):
        raise HTTPException(status_code=503, detail="AI provider is not configured")
    if not record_attempt(
        session, user.id, "chat_answer", settings.analysis_limit_per_hour
    ):
        raise HTTPException(
            status_code=429,
            detail="Chat answer limit exceeded",
            headers={"Retry-After": "3600"},
        )
    owned_conversation(session, user, conversation_id, lock=True)
    job = get_answer_job(session, conversation_id, job_id, lock=True)
    if job is None:
        raise HTTPException(status_code=404, detail="Answer job not found")
    if job.status != "failed":
        raise HTTPException(status_code=409, detail="Only failed jobs can be retried")
    job.status = "queued"
    job.error_code = None
    job.allow_provider_fallbacks = body.allow_provider_fallbacks
    session.commit()
    session.refresh(job)
    return AnswerJobResponse.model_validate(job)
