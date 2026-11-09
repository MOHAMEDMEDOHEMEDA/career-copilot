from test_adaptive_evaluation import evaluation_data

from career_copilot_backend.schemas.adaptive_interview import AdaptiveEvaluation
from career_copilot_backend.services.interview_orchestrator import (
    InterviewState,
    is_duplicate_question,
    plan_next,
    plan_topics,
)
from career_copilot_backend.services.interview_profile import build_candidate_context


def test_profile_only_attributes_exact_resume_evidence():
    context = build_candidate_context(
        "Synthetic project: SwiftUI with Combine.", ["Kotlin", "swiftui"]
    )
    assert {item.name for item in context.resume_skills} == {"SwiftUI", "Combine"}
    assert all(
        item.evidence in "Synthetic project: SwiftUI with Combine."
        for item in context.resume_skills
    )
    assert context.selected_skills == ("Kotlin", "swiftui")
    assert "Kotlin" not in {item.name for item in context.resume_skills}
    assert not build_candidate_context(None, ["Kotlin"]).resume_skills


def test_orchestrator_uses_deterministic_policy_and_recognizes_duplicates():
    state = InterviewState(
        seniority="mid",
        difficulty=3,
        topic="Concurrency",
        remaining_topics=("Networking",),
        follow_up_count=2,
        question_history=("How do Swift actors prevent data races?",),
    )
    decision = plan_next(state, AdaptiveEvaluation.model_validate(evaluation_data()))
    assert decision.action == "new_topic" and decision.topic == "Networking"
    assert is_duplicate_question(
        "How do Swift actors prevent data races!", state.question_history
    )
    assert not is_duplicate_question("What is URLSession?", state.question_history)
    assert plan_topics("Engineer", ["Kotlin", "swiftui"], ["SwiftUI", "Combine"]) == (
        "Kotlin",
        "swiftui",
        "Combine",
    )
