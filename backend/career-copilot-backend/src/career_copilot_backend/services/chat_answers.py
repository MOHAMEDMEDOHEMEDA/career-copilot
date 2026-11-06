import asyncio
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from sqlalchemy import select, update
from sqlalchemy.orm import Session, sessionmaker

from career_copilot_backend.core.config import settings
from career_copilot_backend.knowledge.embeddings import EmbeddingError, OllamaEmbedder
from career_copilot_backend.llm.alternatives import FallbackProvider
from career_copilot_backend.llm.provider import LLMProvider, ProviderError
from career_copilot_backend.models import ChatAnswerJob, ChatMessage, Conversation
from career_copilot_backend.schemas.rag import CitedAnswer
from career_copilot_backend.services.analysis import (
    AnalysisInputError,
    AnalysisOutputError,
)
from career_copilot_backend.services.rag import answer_question


def get_answer_job(
    session: Session, conversation_id: UUID, job_id: UUID, *, lock: bool = False
) -> ChatAnswerJob | None:
    query = select(ChatAnswerJob).where(
        ChatAnswerJob.id == job_id, ChatAnswerJob.conversation_id == conversation_id
    )
    return session.scalar(
        query.with_for_update().execution_options(populate_existing=True)
        if lock
        else query
    )


def queue_answer(
    session: Session,
    conversation: Conversation,
    question_id: UUID,
    allow_fallbacks: bool,
) -> ChatAnswerJob | None:
    question = session.scalar(
        select(ChatMessage).where(
            ChatMessage.id == question_id,
            ChatMessage.conversation_id == conversation.id,
            ChatMessage.role == "user",
        )
    )
    if question is None:
        return None
    job = session.scalar(
        select(ChatAnswerJob).where(ChatAnswerJob.question_id == question_id)
    )
    if job is not None:
        return job
    job = ChatAnswerJob(
        conversation_id=conversation.id,
        question_id=question_id,
        allow_provider_fallbacks=allow_fallbacks,
    )
    session.add(job)
    session.commit()
    session.refresh(job)
    return job


def process_chat_answer(
    sessions: sessionmaker[Session], provider: LLMProvider, job_id: UUID
) -> CitedAnswer:
    with sessions() as session:
        job = session.get(ChatAnswerJob, job_id)
        if job is None:
            raise ValueError("Answer job not found")
        question = session.get(ChatMessage, job.question_id)
        if (
            question is None
            or question.conversation_id != job.conversation_id
            or question.role != "user"
        ):
            raise ValueError("Question not found")
        if isinstance(provider, FallbackProvider):
            provider = provider.for_consent(job.allow_provider_fallbacks)
        return asyncio.run(
            answer_question(
                session,
                OllamaEmbedder(settings.ollama_base_url),
                provider,
                question.content,
            )
        )


def run_next_chat_answer(
    sessions: sessionmaker[Session],
    handler: Callable[[UUID], CitedAnswer],
    lease_seconds: int = 300,
) -> bool:
    now = datetime.now(UTC)
    with sessions() as session:
        session.execute(
            update(ChatAnswerJob)
            .where(
                ChatAnswerJob.status == "running", ChatAnswerJob.lease_expires_at < now
            )
            .values(
                status="failed",
                error_code="timeout",
                lease_id=None,
                lease_expires_at=None,
            )
        )
        job = session.scalar(
            select(ChatAnswerJob)
            .where(ChatAnswerJob.status == "queued")
            .order_by(ChatAnswerJob.created_at, ChatAnswerJob.id)
            .with_for_update(skip_locked=True)
            .limit(1)
        )
        if job is None:
            session.commit()
            return False
        lease = uuid4()
        job.status = "running"
        job.lease_id = lease
        job.lease_expires_at = now + timedelta(seconds=lease_seconds)
        job.attempts += 1
        job_id = job.id
        session.commit()
    try:
        result = handler(job_id)
        error_code = None
    except Exception as exc:  # noqa: BLE001 - record failures without leaking provider data
        result = None
        if isinstance(exc, ProviderError):
            error_code = (
                exc.code
                if exc.code
                in {
                    "rate_limited",
                    "provider_error",
                    "provider_auth",
                    "provider_unavailable",
                    "output_limit",
                    "timeout",
                    "invalid_output",
                }
                else "provider_error"
            )
        elif isinstance(exc, EmbeddingError):
            error_code = "provider_unavailable"
        elif isinstance(exc, AnalysisOutputError):
            error_code = "invalid_output"
        elif isinstance(exc, AnalysisInputError):
            error_code = "invalid_input"
        else:
            error_code = (
                "timeout" if isinstance(exc, TimeoutError) else "analysis_failed"
            )
    with sessions() as session:
        snapshot = session.get(ChatAnswerJob, job_id)
        if snapshot is None:
            return True
        conversation = session.scalar(
            select(Conversation)
            .where(Conversation.id == snapshot.conversation_id)
            .with_for_update()
        )
        if conversation is None:
            return True
        job = session.scalar(
            select(ChatAnswerJob)
            .where(
                ChatAnswerJob.id == job_id,
                ChatAnswerJob.lease_id == lease,
                ChatAnswerJob.status == "running",
            )
            .with_for_update()
            .execution_options(populate_existing=True)
        )
        if job is None:
            return True
        if result is not None:
            conversation.message_count += 1
            message = ChatMessage(
                conversation_id=conversation.id,
                sequence=conversation.message_count,
                role="assistant",
                content=result.answer,
                citations=[citation.model_dump() for citation in result.citations],
                insufficient_information=result.insufficient_information,
                reply_to_id=job.question_id,
            )
            session.add(message)
            session.flush()
            job.answer_message_id = message.id
            job.status = "completed"
            job.error_code = None
        else:
            job.status = "failed"
            job.error_code = error_code
        job.lease_id = None
        job.lease_expires_at = None
        session.commit()
    return True
