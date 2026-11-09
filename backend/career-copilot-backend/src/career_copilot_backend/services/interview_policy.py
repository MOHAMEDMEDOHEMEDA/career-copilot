from dataclasses import dataclass
from typing import Literal

from career_copilot_backend.schemas.adaptive_interview import (
    AdaptiveEvaluation,
    Seniority,
)

Action = Literal["deepen", "clarify", "challenge", "new_topic", "complete"]
DIFFICULTY_BOUNDS: dict[Seniority, tuple[int, int]] = {
    "junior": (1, 3),
    "mid": (2, 4),
    "senior": (3, 5),
}
MAX_FOLLOW_UPS = 2


@dataclass(frozen=True)
class InterviewDecision:
    action: Action
    difficulty: int
    topic: str
    follow_up_count: int


def decide_next(
    *,
    evaluation: AdaptiveEvaluation,
    seniority: Seniority,
    difficulty: int,
    topic: str,
    remaining_topics: list[str],
    follow_up_count: int,
    max_follow_ups: int = MAX_FOLLOW_UPS,
) -> InterviewDecision:
    low, high = DIFFICULTY_BOUNDS[seniority]
    if (
        not low <= difficulty <= high
        or follow_up_count < 0
        or max_follow_ups < 0
        or not topic.strip()
    ):
        raise ValueError("Invalid interview state")
    if follow_up_count >= max_follow_ups:
        if remaining_topics:
            return InterviewDecision("new_topic", difficulty, remaining_topics[0], 0)
        return InterviewDecision("complete", difficulty, topic, follow_up_count)
    if evaluation.classification in {"incorrect", "not_assessable"} or (
        evaluation.overall_score is not None and evaluation.overall_score <= 1
    ):
        return InterviewDecision(
            "clarify", max(low, difficulty - 1), topic, follow_up_count + 1
        )
    if evaluation.classification == "partially_correct" and evaluation.inaccuracies:
        return InterviewDecision("challenge", difficulty, topic, follow_up_count + 1)
    if (
        evaluation.classification == "partially_correct"
        or evaluation.overall_score is None
        or evaluation.overall_score == 2
    ):
        return InterviewDecision("clarify", difficulty, topic, follow_up_count + 1)
    return InterviewDecision(
        "deepen", min(high, difficulty + 1), topic, follow_up_count + 1
    )
