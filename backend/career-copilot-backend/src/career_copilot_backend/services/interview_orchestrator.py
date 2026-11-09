import re
from dataclasses import dataclass

from career_copilot_backend.schemas.adaptive_interview import (
    AdaptiveEvaluation,
    Seniority,
)
from career_copilot_backend.services.interview_policy import (
    InterviewDecision,
    decide_next,
)


@dataclass(frozen=True)
class InterviewState:
    seniority: Seniority
    difficulty: int
    topic: str
    remaining_topics: tuple[str, ...]
    follow_up_count: int
    question_history: tuple[str, ...]


def plan_topics(
    role: str, selected: list[str], resume_mentions: list[str], *, limit: int = 8
) -> tuple[str, ...]:
    topics: list[str] = []
    seen: set[str] = set()
    for item in [*selected, *resume_mentions]:
        topic = item.strip()
        if topic and topic.casefold() not in seen:
            seen.add(topic.casefold())
            topics.append(topic)
            if len(topics) >= limit:
                break
    return tuple(topics or [role.strip()])


def plan_next(
    state: InterviewState, evaluation: AdaptiveEvaluation, *, max_followups: int = 2
) -> InterviewDecision:
    return decide_next(
        evaluation=evaluation,
        seniority=state.seniority,
        difficulty=state.difficulty,
        topic=state.topic,
        remaining_topics=list(state.remaining_topics),
        follow_up_count=state.follow_up_count,
        max_follow_ups=max_followups,
    )


def is_duplicate_question(candidate: str, history: tuple[str, ...]) -> bool:
    def tokens(value: str) -> set[str]:
        return set(re.findall(r"\w+", value.casefold()))

    proposed = tokens(candidate)
    if not proposed:
        return True
    for question in history:
        previous = tokens(question)
        if previous and len(proposed & previous) / len(proposed | previous) >= 0.9:
            return True
    return False
