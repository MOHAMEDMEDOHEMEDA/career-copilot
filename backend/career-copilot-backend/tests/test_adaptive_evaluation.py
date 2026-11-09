import json

import pytest
from pydantic import ValidationError

from career_copilot_backend.llm.alternatives import FallbackProvider
from career_copilot_backend.llm.provider import ProviderError
from career_copilot_backend.schemas.adaptive_interview import AdaptiveEvaluation
from career_copilot_backend.schemas.rag import Citation
from career_copilot_backend.services.adaptive_evaluation import evaluate_adaptive_answer
from career_copilot_backend.services.analysis import AnalysisOutputError
from career_copilot_backend.services.interview_policy import decide_next


def evaluation_data(score=3, classification="correct"):
    criterion = {"score": score, "explanation": "Synthetic assessment"}
    return {
        "classification": classification,
        "overall_score": score,
        "correctness": criterion,
        "completeness": criterion,
        "reasoning": criterion,
        "communication": criterion,
        "demonstrated_concepts": ["Isolation"],
        "missing_concepts": [],
        "inaccuracies": [],
        "evidence": ["prevent data races"],
        "suggested_action": "challenge",
        "feedback": "Explain the limitation.",
    }


class FakeProvider:
    def __init__(self, data):
        self.data = data
        self.calls = []

    async def generate_structured(self, **kwargs):
        self.calls.append(kwargs)
        return json.dumps(self.data)


@pytest.mark.asyncio
async def test_fallback_rejects_ungrounded_evidence_before_trying_next_provider():
    invalid = evaluation_data()
    invalid["evidence"] = ["invented experience"]
    first, second = FakeProvider(invalid), FakeProvider(evaluation_data())
    result = await evaluate_adaptive_answer(
        FallbackProvider([first, second]), question="What are actors?",
        answer="Actors help prevent data races.", topic="Concurrency", difficulty=3,
    )
    assert result.evidence == ["prevent data races"]
    assert len(first.calls) == len(second.calls) == 1


@pytest.mark.asyncio
async def test_fallback_rejects_all_ungrounded_results():
    invalid = evaluation_data()
    invalid["reference_ids"] = ["invented:0"]
    first, second = FakeProvider(invalid), FakeProvider(invalid)
    with pytest.raises(ProviderError) as exc:
        await evaluate_adaptive_answer(
            FallbackProvider([first, second]), question="What are actors?",
            answer="Actors help prevent data races.", topic="Concurrency", difficulty=3,
        )
    assert exc.value.code == "invalid_output"
    assert len(first.calls) == len(second.calls) == 1


@pytest.mark.asyncio
@pytest.mark.parametrize("answer", ["I don't know.", "I dont know", "No idea!"])
async def test_unknown_answer_gets_unscored_example(answer):
    data = evaluation_data(score=None, classification="not_assessable")
    data.update(demonstrated_concepts=[], evidence=[], example_answer="Actors isolate mutable state.")
    result = await evaluate_adaptive_answer(
        FakeProvider(data), question="What are actors?", answer=answer,
        topic="Concurrency", difficulty=3,
    )
    assert result.example_answer == "Actors isolate mutable state."
    assert result.overall_score is None
    assert not result.demonstrated_concepts


@pytest.mark.asyncio
async def test_unknown_answer_rejects_scored_or_missing_example():
    for data in (evaluation_data(), {
        **evaluation_data(score=None, classification="not_assessable"),
        "demonstrated_concepts": [], "evidence": [],
    }):
        with pytest.raises(AnalysisOutputError):
            await evaluate_adaptive_answer(
                FakeProvider(data), question="What are actors?", answer="I don't know.",
                topic="Concurrency", difficulty=3,
            )


@pytest.mark.asyncio
async def test_evaluation_checks_actual_answer_and_untrusted_content():
    provider = FakeProvider(evaluation_data())
    result = await evaluate_adaptive_answer(
        provider,
        question="What are actors?",
        answer="Actors help prevent data races.",
        topic="Concurrency",
        difficulty=3,
    )
    assert result.overall_score == 3
    assert "untrusted" in provider.calls[0]["system_instruction"]
    assert (
        json.loads(provider.calls[0]["untrusted_text"])["answer"]
        == "Actors help prevent data races."
    )
    await evaluate_adaptive_answer(
        provider,
        question="Describe collaboration.",
        answer="We worked to prevent data races.",
        topic="Collaboration",
        difficulty=2,
        question_type="behavioral",
    )
    payload = json.loads(provider.calls[-1]["untrusted_text"])
    assert (
        payload["question_type"] == "behavioral"
        and "not applicable" in payload["rubric"]
    )
    provider.data["evidence"] = ["invented experience"]
    with pytest.raises(AnalysisOutputError):
        await evaluate_adaptive_answer(
            provider,
            question="What are actors?",
            answer="Actors help prevent data races.",
            topic="Concurrency",
            difficulty=3,
        )


@pytest.mark.asyncio
async def test_evaluation_accepts_only_supplied_reference_ids():
    source = Citation(
        chunk_id="reference:0",
        source_id="reference",
        title="Reference",
        origin="Reviewed",
        excerpt="Synthetic reference.",
    )
    data = evaluation_data()
    data["reference_ids"] = ["reference:0"]
    result = await evaluate_adaptive_answer(
        FakeProvider(data),
        question="What are actors?",
        answer="Actors help prevent data races.",
        topic="Concurrency",
        difficulty=3,
        references=[source],
        reference_versions={"reference:0": "1"},
    )
    assert result.references == [source]
    assert result.reference_versions == {"reference:0": "1"}
    data["reference_ids"] = ["invented:0"]
    with pytest.raises(AnalysisOutputError):
        await evaluate_adaptive_answer(
            FakeProvider(data),
            question="What are actors?",
            answer="Actors help prevent data races.",
            topic="Concurrency",
            difficulty=3,
            references=[source],
        )


def test_evaluation_rejects_invalid_scores_and_unsupported_assessment():
    invalid = evaluation_data(score=5)
    with pytest.raises(ValidationError):
        AdaptiveEvaluation.model_validate(invalid)
    unsupported = evaluation_data()
    unsupported["evidence"] = []
    with pytest.raises(ValidationError):
        AdaptiveEvaluation.model_validate(unsupported)
    unsupported = evaluation_data(classification="not_assessable")
    with pytest.raises(ValidationError):
        AdaptiveEvaluation.model_validate(unsupported)


def test_policy_adapts_within_seniority_and_limits_followups():
    strong = AdaptiveEvaluation.model_validate(evaluation_data(score=4))
    partial = AdaptiveEvaluation.model_validate(
        evaluation_data(score=2, classification="partially_correct")
    )
    weak = AdaptiveEvaluation.model_validate(
        evaluation_data(score=0, classification="incorrect")
    )
    args = {
        "seniority": "mid",
        "difficulty": 3,
        "topic": "Concurrency",
        "remaining_topics": ["Networking"],
        "follow_up_count": 0,
    }
    assert decide_next(evaluation=strong, **args).difficulty == 4
    assert decide_next(evaluation=partial, **args).action == "clarify"
    challenge_data = evaluation_data(score=2, classification="partially_correct")
    challenge_data["inaccuracies"] = ["A questionable assumption"]
    assert (
        decide_next(
            evaluation=AdaptiveEvaluation.model_validate(challenge_data), **args
        ).action
        == "challenge"
    )
    assert decide_next(evaluation=weak, **args).difficulty == 2
    decision = decide_next(evaluation=strong, **{**args, "follow_up_count": 2})
    assert decision.action == "new_topic" and decision.topic == "Networking"
    decision = decide_next(
        evaluation=strong, **{**args, "follow_up_count": 2, "remaining_topics": []}
    )
    assert decision.action == "complete"
