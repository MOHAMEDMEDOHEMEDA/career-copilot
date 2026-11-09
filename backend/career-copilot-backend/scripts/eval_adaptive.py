"""Synthetic deterministic policy smoke check; does not measure model quality."""

import json
from pathlib import Path

from career_copilot_backend.schemas.adaptive_interview import AdaptiveEvaluation
from career_copilot_backend.services.interview_policy import decide_next


def main() -> None:
    path = (
        Path(__file__).resolve().parents[1]
        / "fixtures"
        / "adaptive_interview_eval.json"
    )
    cases = json.loads(path.read_text(encoding="utf-8"))
    passed = 0
    for case in cases:
        assert case["evidence"] in case["answer"]
        criterion = {"score": case["score"], "explanation": "Synthetic fixture."}
        evaluation = AdaptiveEvaluation.model_validate(
            {
                "classification": case["classification"],
                "overall_score": case["score"],
                "correctness": criterion,
                "completeness": criterion,
                "reasoning": criterion,
                "communication": criterion,
                "demonstrated_concepts": [],
                "missing_concepts": [],
                "inaccuracies": [],
                "evidence": [case["evidence"]],
                "suggested_action": "new_topic",
                "feedback": "Synthetic fixture.",
            }
        )
        decision = decide_next(
            evaluation=evaluation,
            seniority="mid",
            difficulty=3,
            topic=case["topic"],
            remaining_topics=["Next topic"],
            follow_up_count=0,
        )
        if (
            decision.action == case["expected_action"]
            and decision.difficulty == case["expected_difficulty"]
        ):
            passed += 1
    print(
        f"Adaptive policy smoke cases: {passed}/{len(cases)} passed (model quality not evaluated)"
    )
    if passed != len(cases):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
