from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from career_copilot_backend.core.config import settings
from career_copilot_backend.models import (
    AdaptiveInterviewJob,
    AdaptiveInterviewSession,
    AdaptiveInterviewTurn,
)
from career_copilot_backend.schemas.adaptive_interview import (
    AdaptiveEvaluation,
    AdaptiveInterviewCreate,
    AdaptiveReport,
    Seniority,
    TopicProgress,
)
from career_copilot_backend.services.interview_orchestrator import (
    InterviewState,
    plan_next,
)


def create_session(
    db: Session, user_id: UUID, data: AdaptiveInterviewCreate
) -> AdaptiveInterviewSession:
    item = AdaptiveInterviewSession(
        user_id=user_id,
        **data.model_dump(),
        current_difficulty={"junior": 1, "mid": 3, "senior": 5}[data.seniority],
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return item


def find_session(
    db: Session, user_id: UUID, session_id: UUID, *, lock: bool = False
) -> AdaptiveInterviewSession | None:
    query = select(AdaptiveInterviewSession).where(
        AdaptiveInterviewSession.id == session_id,
        AdaptiveInterviewSession.user_id == user_id,
    )
    return db.scalar(query.with_for_update() if lock else query)


def list_sessions(
    db: Session, user_id: UUID, limit: int, offset: int
) -> list[AdaptiveInterviewSession]:
    return list(
        db.scalars(
            select(AdaptiveInterviewSession)
            .where(AdaptiveInterviewSession.user_id == user_id)
            .order_by(
                AdaptiveInterviewSession.created_at.desc(),
                AdaptiveInterviewSession.id.desc(),
            )
            .limit(limit)
            .offset(offset)
        )
    )


def delete_session(db: Session, item: AdaptiveInterviewSession) -> None:
    db.execute(
        delete(AdaptiveInterviewJob).where(AdaptiveInterviewJob.session_id == item.id)
    )
    db.execute(
        delete(AdaptiveInterviewTurn).where(AdaptiveInterviewTurn.session_id == item.id)
    )
    db.delete(item)
    db.commit()


def list_turns(
    db: Session, session_id: UUID, limit: int, offset: int
) -> list[AdaptiveInterviewTurn]:
    return list(
        db.scalars(
            select(AdaptiveInterviewTurn)
            .where(AdaptiveInterviewTurn.session_id == session_id)
            .order_by(AdaptiveInterviewTurn.sequence)
            .limit(limit)
            .offset(offset)
        )
    )


def last_turn(db: Session, session_id: UUID) -> AdaptiveInterviewTurn | None:
    return db.scalar(
        select(AdaptiveInterviewTurn)
        .where(AdaptiveInterviewTurn.session_id == session_id)
        .order_by(AdaptiveInterviewTurn.sequence.desc())
        .limit(1)
    )


def has_next_topic(
    interview: AdaptiveInterviewSession, turn: AdaptiveInterviewTurn
) -> bool:
    if turn.evaluation is None:
        return False
    evaluation = AdaptiveEvaluation.model_validate(turn.evaluation)
    seniority: Seniority = interview.seniority  # type: ignore[assignment]
    state = InterviewState(
        seniority=seniority,
        difficulty=interview.current_difficulty,
        topic=turn.topic,
        remaining_topics=tuple(
            topic for topic in interview.topics if topic not in interview.covered_topics
        ),
        follow_up_count=interview.follow_up_count,
        question_history=(),
    )
    return (
        plan_next(
            state, evaluation, max_followups=settings.adaptive_max_followups
        ).action
        != "complete"
    )


def get_turn(
    db: Session, session_id: UUID, turn_id: UUID
) -> AdaptiveInterviewTurn | None:
    return db.scalar(
        select(AdaptiveInterviewTurn).where(
            AdaptiveInterviewTurn.id == turn_id,
            AdaptiveInterviewTurn.session_id == session_id,
        )
    )


def save_answer(
    db: Session,
    interview: AdaptiveInterviewSession,
    turn: AdaptiveInterviewTurn,
    answer: str,
) -> AdaptiveInterviewTurn:
    if turn.answer != answer:
        turn.answer = answer
        turn.answer_revision += 1
        turn.evaluation = None
        interview.state_version += 1
    db.commit()
    db.refresh(turn)
    return turn


def find_job(
    db: Session, session_id: UUID, job_id: UUID, *, lock: bool = False
) -> AdaptiveInterviewJob | None:
    query = select(AdaptiveInterviewJob).where(
        AdaptiveInterviewJob.id == job_id,
        AdaptiveInterviewJob.session_id == session_id,
    )
    return db.scalar(
        query.with_for_update().execution_options(populate_existing=True)
        if lock
        else query
    )


def list_jobs(
    db: Session, session_id: UUID, limit: int, offset: int
) -> list[AdaptiveInterviewJob]:
    return list(
        db.scalars(
            select(AdaptiveInterviewJob)
            .where(AdaptiveInterviewJob.session_id == session_id)
            .order_by(
                AdaptiveInterviewJob.created_at.desc(), AdaptiveInterviewJob.id.desc()
            )
            .limit(limit)
            .offset(offset)
        )
    )


def retry_job(
    db: Session, job: AdaptiveInterviewJob, allow_fallbacks: bool
) -> AdaptiveInterviewJob:
    job.status = "queued"
    job.error_code = None
    job.allow_provider_fallbacks = allow_fallbacks
    db.commit()
    db.refresh(job)
    return job


def job_key(
    interview: AdaptiveInterviewSession, turn: AdaptiveInterviewTurn | None
) -> str:
    return (
        f"evaluation:{turn.id}:{turn.answer_revision}"
        if turn
        else f"next:{interview.id}:{interview.state_version}"
    )


def existing_job(db: Session, key: str) -> AdaptiveInterviewJob | None:
    return db.scalar(
        select(AdaptiveInterviewJob).where(AdaptiveInterviewJob.dedup_key == key)
    )


def queue_job(
    db: Session,
    interview: AdaptiveInterviewSession,
    turn: AdaptiveInterviewTurn | None,
    allow_fallbacks: bool,
) -> AdaptiveInterviewJob:
    key = job_key(interview, turn)
    if existing := existing_job(db, key):
        return existing
    job = AdaptiveInterviewJob(
        session_id=interview.id,
        turn_id=turn.id if turn else None,
        kind="evaluation" if turn else "next",
        dedup_key=key,
        state_version=interview.state_version,
        answer_revision=turn.answer_revision if turn else None,
        allow_provider_fallbacks=allow_fallbacks,
    )
    db.add(job)
    db.commit()
    db.refresh(job)
    return job


def complete_session(
    db: Session, interview: AdaptiveInterviewSession
) -> AdaptiveInterviewSession:
    if interview.status != "completed":
        interview.status = "completed"
        interview.completed_at = datetime.now(UTC)
        interview.state_version += 1
        db.commit()
        db.refresh(interview)
    return interview


def make_report(db: Session, interview: AdaptiveInterviewSession) -> AdaptiveReport:
    turns = list(
        db.scalars(
            select(AdaptiveInterviewTurn)
            .where(AdaptiveInterviewTurn.session_id == interview.id)
            .order_by(AdaptiveInterviewTurn.sequence)
        )
    )
    scores: list[int] = []
    by_topic: dict[str, list[int]] = {}
    missing: list[str] = []
    count = 0
    for turn in turns:
        if turn.evaluation is None:
            continue
        evaluation = AdaptiveEvaluation.model_validate(turn.evaluation)
        count += 1
        if evaluation.overall_score is not None and evaluation.evidence:
            scores.append(evaluation.overall_score)
            by_topic.setdefault(turn.topic, []).append(evaluation.overall_score)
        for concept in evaluation.missing_concepts:
            if concept not in missing:
                missing.append(concept)
    progress = [
        TopicProgress(
            topic=topic,
            average_score=round(sum(values) / len(values), 2),
            evidence_count=len(values),
        )
        for topic, values in by_topic.items()
    ]
    sufficient = [item for item in progress if item.evidence_count >= 2]
    strongest = sorted(
        (item for item in sufficient if item.average_score >= 3),
        key=lambda item: (-item.average_score, item.topic),
    )
    weakest = sorted(
        (item for item in sufficient if item.average_score < 3),
        key=lambda item: (item.average_score, item.topic),
    )
    average = round(sum(scores) / len(scores), 2) if scores else None
    previous_average = None
    if len(scores) >= 2 and interview.completed_at is not None:
        previous_sessions = db.scalars(
            select(AdaptiveInterviewSession)
            .where(
                AdaptiveInterviewSession.user_id == interview.user_id,
                AdaptiveInterviewSession.id != interview.id,
                AdaptiveInterviewSession.status == "completed",
                AdaptiveInterviewSession.role == interview.role,
                AdaptiveInterviewSession.seniority == interview.seniority,
                AdaptiveInterviewSession.completed_at < interview.completed_at,
            )
            .order_by(AdaptiveInterviewSession.completed_at.desc())
            .limit(20)
        )
        for previous in previous_sessions:
            previous_turns = db.scalars(
                select(AdaptiveInterviewTurn).where(
                    AdaptiveInterviewTurn.session_id == previous.id,
                    AdaptiveInterviewTurn.evaluation.is_not(None),
                )
            )
            previous_scores = []
            for previous_turn in previous_turns:
                evaluation = AdaptiveEvaluation.model_validate(previous_turn.evaluation)
                if evaluation.overall_score is not None and evaluation.evidence:
                    previous_scores.append(evaluation.overall_score)
            if len(previous_scores) >= 2:
                previous_average = round(sum(previous_scores) / len(previous_scores), 2)
                break
    return AdaptiveReport(
        session_id=interview.id,
        status="completed",
        evaluated_answers=count,
        average_score=average,
        topic_progress=progress,
        missing_concepts=missing,
        strongest_topics=[item.topic for item in strongest[:3]],
        study_topics=[item.topic for item in weakest[:3]],
        suggested_questions=[
            f"How would you explain {concept}?" for concept in missing[:5]
        ],
        previous_average_score=previous_average,
        score_change=round(average - previous_average, 2)
        if average is not None and previous_average is not None
        else None,
    )


def skill_progress(
    db: Session, user_id: UUID, limit: int, offset: int
) -> list[TopicProgress]:
    score = AdaptiveInterviewTurn.evaluation["overall_score"].as_integer()
    rows = db.execute(
        select(AdaptiveInterviewTurn.topic, func.avg(score), func.count(score))
        .join(
            AdaptiveInterviewSession,
            AdaptiveInterviewTurn.session_id == AdaptiveInterviewSession.id,
        )
        .where(
            AdaptiveInterviewSession.user_id == user_id,
            AdaptiveInterviewSession.status == "completed",
            score.is_not(None),
        )
        .group_by(AdaptiveInterviewTurn.topic)
        .having(func.count(score) >= 2)
        .order_by(AdaptiveInterviewTurn.topic)
        .limit(limit)
        .offset(offset)
    )
    return [
        TopicProgress(
            topic=topic, average_score=round(float(average), 2), evidence_count=count
        )
        for topic, average, count in rows
    ]
