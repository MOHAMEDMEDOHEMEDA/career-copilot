import asyncio
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from sqlalchemy import select, update
from sqlalchemy.orm import Session, sessionmaker

from career_copilot_backend.core.config import settings
from career_copilot_backend.knowledge.corpus import (
    chunk_sources,
    load_corpus,
    select_reviewed_sources,
)
from career_copilot_backend.knowledge.embeddings import EmbeddingError, OllamaEmbedder
from career_copilot_backend.knowledge.index import retrieve
from career_copilot_backend.llm.alternatives import FallbackProvider
from career_copilot_backend.llm.provider import LLMProvider, ProviderError
from career_copilot_backend.llm.usage import capture_usage
from career_copilot_backend.models import (
    AdaptiveInterviewJob,
    AdaptiveInterviewSession,
    AdaptiveInterviewTurn,
    Resume,
)
from career_copilot_backend.schemas.adaptive_interview import (
    AdaptiveEvaluation,
    Seniority,
)
from career_copilot_backend.schemas.rag import Citation
from career_copilot_backend.services.adaptive_evaluation import evaluate_adaptive_answer
from career_copilot_backend.services.adaptive_question import generate_adaptive_question
from career_copilot_backend.services.analysis import (
    AnalysisInputError,
    AnalysisOutputError,
)
from career_copilot_backend.services.interview_orchestrator import (
    InterviewState,
    plan_next,
    plan_topics,
)
from career_copilot_backend.services.interview_profile import build_candidate_context


@dataclass(frozen=True)
class GeneratedTurn:
    prompt: str
    topic: str
    difficulty: int
    follow_up_count: int
    topics: tuple[str, ...]
    covered_topics: tuple[str, ...]
    question_type: str = "technical"


def process_adaptive_job(
    sessions: sessionmaker[Session], provider: LLMProvider, job_id: UUID
) -> GeneratedTurn | AdaptiveEvaluation:
    with sessions() as db:
        job = db.get(AdaptiveInterviewJob, job_id)
        if job is None:
            raise AnalysisInputError("Job not found")
        interview = db.get(AdaptiveInterviewSession, job.session_id)
        if (
            interview is None
            or interview.status != "active"
            or interview.state_version != job.state_version
        ):
            raise AnalysisInputError("Interview is no longer current")
        resume = db.get(Resume, interview.resume_id) if interview.resume_id else None
        if interview.resume_id and (
            resume is None or resume.user_id != interview.user_id
        ):
            raise AnalysisInputError("Resume not found")
        if isinstance(provider, FallbackProvider):
            provider = provider.for_consent(job.allow_provider_fallbacks)
        turns = list(
            db.scalars(
                select(AdaptiveInterviewTurn)
                .where(AdaptiveInterviewTurn.session_id == interview.id)
                .order_by(AdaptiveInterviewTurn.sequence)
            )
        )
        if job.kind == "evaluation":
            turn = next((item for item in turns if item.id == job.turn_id), None)
            if (
                turn is None
                or not turn.answer
                or turn.answer_revision != job.answer_revision
            ):
                raise AnalysisInputError("Answer is no longer current")
            source_ids = tuple(
                item.strip()
                for item in settings.reviewed_technical_source_ids.split(",")
                if item.strip()
            )[:100]
            references = []
            reference_versions: dict[str, str] = {}
            if source_ids and turn.question_type == "technical":
                sources = select_reviewed_sources(
                    load_corpus(),
                    source_ids,
                    role=interview.role,
                    topic=turn.topic,
                    difficulty=turn.difficulty,
                )
                eligible = tuple(source.id for source in sources)
                current_chunks = {chunk.id: chunk for chunk in chunk_sources(sources)}
                versions = {source.id: source.version for source in sources}
            else:
                eligible = ()
                current_chunks = {}
                versions = {}
            if eligible:
                vector = OllamaEmbedder(settings.ollama_base_url).embed(
                    [f"{turn.topic}: {turn.prompt}"], query=True
                )[0]
                if settings.knowledge_hybrid_enabled:
                    retrieved = retrieve(
                        db, vector, source_ids=eligible,
                        query_text=f"{turn.topic}: {turn.prompt}", hybrid=True,
                        max_distance=settings.knowledge_vector_max_distance,
                        keyword_max_distance=settings.knowledge_keyword_max_distance,
                    )
                elif settings.knowledge_vector_max_distance != 0.35:
                    retrieved = retrieve(db, vector, source_ids=eligible, max_distance=settings.knowledge_vector_max_distance)
                else:
                    retrieved = retrieve(db, vector, source_ids=eligible)
                for chunk in retrieved:
                    current = current_chunks.get(chunk.id)
                    if current is None or (
                        chunk.content,
                        chunk.title,
                        chunk.origin,
                    ) != (current.content, current.title, current.origin):
                        continue
                    references.append(
                        Citation(
                            chunk_id=chunk.id,
                            source_id=chunk.source_id,
                            title=chunk.title,
                            origin=chunk.origin,
                            excerpt=chunk.content,
                        )
                    )
                    reference_versions[chunk.id] = versions[chunk.source_id]
            return asyncio.run(
                evaluate_adaptive_answer(
                    provider,
                    question=turn.prompt,
                    answer=turn.answer,
                    topic=turn.topic,
                    difficulty=turn.difficulty,
                    question_type=turn.question_type,
                    references=references,
                    reference_versions=reference_versions,
                )
            )
        profile = build_candidate_context(
            resume.text if resume else None, interview.skills
        )
        topics = (
            tuple(interview.topics)
            if interview.topics
            else plan_topics(
                interview.role,
                interview.skills,
                [item.name for item in profile.resume_skills],
            )
        )
        covered = list(interview.covered_topics)
        history = tuple(item.prompt for item in turns)
        if not turns:
            topic, difficulty, action, followups = (
                topics[0],
                interview.current_difficulty,
                "new_topic",
                0,
            )
            covered.append(topic)
            question_type = (
                "technical"
                if interview.interview_type == "mixed"
                else interview.interview_type
            )
        else:
            previous = turns[-1]
            if not previous.answer or previous.evaluation is None:
                raise AnalysisInputError("Current answer has not been evaluated")
            evaluation = AdaptiveEvaluation.model_validate(previous.evaluation)
            remaining = tuple(item for item in topics if item not in covered)
            seniority: Seniority = interview.seniority  # type: ignore[assignment]
            decision = plan_next(
                InterviewState(
                    seniority=seniority,
                    difficulty=interview.current_difficulty,
                    topic=previous.topic,
                    remaining_topics=remaining,
                    follow_up_count=interview.follow_up_count,
                    question_history=history,
                ),
                evaluation,
                max_followups=settings.adaptive_max_followups,
            )
            if decision.action == "complete":
                raise AnalysisInputError("No interview topics remain")
            topic, difficulty, action, followups = (
                decision.topic,
                decision.difficulty,
                decision.action,
                decision.follow_up_count,
            )
            if topic not in covered:
                covered.append(topic)
            question_type = previous.question_type
            if action == "new_topic" and interview.interview_type == "mixed":
                question_type = (
                    "behavioral"
                    if previous.question_type == "technical"
                    else "technical"
                )
        prompt = asyncio.run(
            generate_adaptive_question(
                provider,
                role=interview.role,
                seniority=interview.seniority,
                interview_type=question_type,
                job_description=interview.job_description,
                topic=topic,
                difficulty=difficulty,
                action=action,
                profile=profile,
                prior_questions=history,
                previous_answer=turns[-1].answer if turns else None,
                previous_feedback={
                    "classification": evaluation.classification,
                    "missing_concepts": evaluation.missing_concepts[:5],
                    "inaccuracies": [
                        item[:200] for item in evaluation.inaccuracies[:5]
                    ],
                }
                if turns
                else None,
            )
        )
        return GeneratedTurn(
            prompt=prompt.prompt,
            topic=topic,
            difficulty=difficulty,
            follow_up_count=followups,
            topics=topics,
            covered_topics=tuple(covered),
            question_type=question_type,
        )


def run_next_adaptive_job(
    sessions: sessionmaker[Session],
    handler: Callable[[UUID], GeneratedTurn | AdaptiveEvaluation],
    lease_seconds: int = 300,
) -> bool:
    now = datetime.now(UTC)
    with sessions() as db:
        db.execute(
            update(AdaptiveInterviewJob)
            .where(
                AdaptiveInterviewJob.status == "running",
                AdaptiveInterviewJob.lease_expires_at < now,
            )
            .values(
                status="failed",
                error_code="timeout",
                lease_id=None,
                lease_expires_at=None,
            )
        )
        job = db.scalar(
            select(AdaptiveInterviewJob)
            .where(AdaptiveInterviewJob.status == "queued")
            .order_by(AdaptiveInterviewJob.created_at, AdaptiveInterviewJob.id)
            .with_for_update(skip_locked=True)
            .limit(1)
        )
        if job is None:
            db.commit()
            return False
        lease = uuid4()
        job.status = "running"
        job.lease_id = lease
        job.lease_expires_at = now + timedelta(seconds=lease_seconds)
        job.attempts += 1
        job_id = job.id
        interview = db.get(AdaptiveInterviewSession, job.session_id)
        user_id = interview.user_id if interview else None
        operation = f"adaptive_{job.kind}"
        db.commit()
    try:
        with capture_usage(sessions, user_id, operation, job_id):
            result = handler(job_id)
        error = None
    except Exception as exc:  # noqa: BLE001 - do not persist personal input or provider errors
        result = None
        if isinstance(exc, ProviderError):
            error = (
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
        elif isinstance(exc, AnalysisOutputError):
            error = "invalid_output"
        elif isinstance(exc, EmbeddingError):
            error = "provider_unavailable"
        elif isinstance(exc, AnalysisInputError):
            error = "invalid_input"
        else:
            error = "timeout" if isinstance(exc, TimeoutError) else "analysis_failed"
    with sessions() as db:
        snapshot = db.get(AdaptiveInterviewJob, job_id)
        if snapshot is None:
            return True
        interview = db.scalar(
            select(AdaptiveInterviewSession)
            .where(AdaptiveInterviewSession.id == snapshot.session_id)
            .with_for_update()
        )
        if interview is None:
            return True
        job = db.scalar(
            select(AdaptiveInterviewJob)
            .where(
                AdaptiveInterviewJob.id == job_id,
                AdaptiveInterviewJob.status == "running",
                AdaptiveInterviewJob.lease_id == lease,
            )
            .with_for_update()
            .execution_options(populate_existing=True)
        )
        if job is None:
            return True
        if interview.status != "active" or interview.state_version != job.state_version:
            job.status = "failed"
            job.error_code = "stale_state"
        elif isinstance(result, GeneratedTurn) and job.kind == "next":
            last_sequence = (
                db.scalar(
                    select(AdaptiveInterviewTurn.sequence)
                    .where(AdaptiveInterviewTurn.session_id == interview.id)
                    .order_by(AdaptiveInterviewTurn.sequence.desc())
                    .limit(1)
                )
                or 0
            )
            db.add(
                AdaptiveInterviewTurn(
                    session_id=interview.id,
                    sequence=last_sequence + 1,
                    topic=result.topic,
                    difficulty=result.difficulty,
                    question_type=result.question_type,
                    prompt=result.prompt,
                )
            )
            interview.current_topic = result.topic
            interview.current_difficulty = result.difficulty
            interview.topics = list(result.topics)
            interview.covered_topics = list(result.covered_topics)
            interview.follow_up_count = result.follow_up_count
            interview.state_version += 1
            job.status = "completed"
            job.error_code = None
        elif isinstance(result, AdaptiveEvaluation) and job.kind == "evaluation":
            turn = db.scalar(
                select(AdaptiveInterviewTurn)
                .where(
                    AdaptiveInterviewTurn.id == job.turn_id,
                    AdaptiveInterviewTurn.session_id == interview.id,
                )
                .with_for_update()
            )
            if turn is None or turn.answer_revision != job.answer_revision:
                job.status = "failed"
                job.error_code = "stale_answer"
            else:
                turn.evaluation = result.model_dump()
                interview.state_version += 1
                job.status = "completed"
                job.error_code = None
        else:
            job.status = "failed"
            job.error_code = error or "invalid_output"
        job.lease_id = None
        job.lease_expires_at = None
        db.commit()
    return True
