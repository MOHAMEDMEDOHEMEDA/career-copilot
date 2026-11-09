import json
from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from uuid import UUID

import test_auth
from sqlalchemy import func, select
from sqlalchemy.orm import Session, sessionmaker
from test_adaptive_evaluation import evaluation_data
from test_chat import headers_for
from test_pdf import make_pdf

from career_copilot_backend.core.config import settings
from career_copilot_backend.knowledge.corpus import Source
from career_copilot_backend.llm.provider import ProviderError
from career_copilot_backend.models import (
    AdaptiveInterviewSession,
    AdaptiveInterviewTurn,
)
from career_copilot_backend.schemas.adaptive_interview import AdaptiveEvaluation
from career_copilot_backend.services.adaptive_jobs import (
    GeneratedTurn,
    process_adaptive_job,
    run_next_adaptive_job,
)

client = test_auth.client
ROOT = "/api/v1/interviews/adaptive/sessions"


def test_sessions_without_resume_are_private_and_deleted(client):
    api, engine = client
    owner = headers_for(api, "adaptive-owner@example.com")
    other = headers_for(api, "adaptive-other@example.com")
    body = {
        "role": "  iOS developer ",
        "seniority": "mid",
        "skills": [" SwiftUI ", "Combine"],
    }
    assert api.post(ROOT, json=body).status_code == 401
    response = api.post(ROOT, headers=owner, json=body)
    assert response.status_code == 201
    item = response.json()
    assert item["role"] == "iOS developer" and item["skills"] == ["SwiftUI", "Combine"]
    assert item["resume_id"] is None and item["status"] == "active"
    assert item["current_difficulty"] == 3 and item["state_version"] == 0
    path = f"{ROOT}/{item['id']}"
    assert api.get(path, headers=other).status_code == 404
    assert api.delete(path, headers=other).status_code == 404
    assert api.get(ROOT, headers=other).json()["items"] == []
    assert api.get(path, headers=owner).json()["id"] == item["id"]
    with Session(engine) as db:
        db.add(
            AdaptiveInterviewTurn(
                session_id=UUID(item["id"]),
                sequence=1,
                topic="Swift",
                difficulty=3,
                question_type="technical",
                prompt="Synthetic question?",
            )
        )
        db.commit()
    assert api.delete(path, headers=owner).status_code == 204
    assert api.get(path, headers=owner).status_code == 404
    with Session(engine) as db:
        assert db.scalar(select(func.count()).select_from(AdaptiveInterviewTurn)) == 0


def test_owned_resume_validation_and_pagination(client):
    api, _ = client
    owner = headers_for(api, "adaptive-resume-owner@example.com")
    other = headers_for(api, "adaptive-resume-other@example.com")
    resume = api.post(
        "/api/v1/resumes",
        headers=owner,
        files={"file": ("synthetic.pdf", make_pdf(True), "application/pdf")},
    ).json()
    body = {"role": "Engineer", "seniority": "junior", "resume_id": resume["id"]}
    assert api.post(ROOT, headers=other, json=body).status_code == 404
    assert api.post(ROOT, headers=owner, json=body).status_code == 201
    assert (
        api.post(
            ROOT, headers=owner, json={"role": "Engineer", "seniority": "senior"}
        ).json()["current_difficulty"]
        == 5
    )
    page = api.get(f"{ROOT}?limit=1&offset=1", headers=owner).json()
    assert len(page["items"]) == 1 and page["limit"] == 1 and page["offset"] == 1
    assert api.get(f"{ROOT}?limit=101", headers=owner).status_code == 422


def test_adaptive_input_validation(client):
    api, _ = client
    owner = headers_for(api, "adaptive-validation@example.com")
    for body in [
        {"role": " ", "seniority": "mid"},
        {"role": "Engineer", "seniority": "principal"},
        {"role": "Engineer", "seniority": "mid", "skills": ["Swift", " SWIFT "]},
        {"role": "Engineer", "seniority": "mid", "skills": [" "]},
        {"role": "Engineer", "seniority": "mid", "status": "completed"},
    ]:
        assert api.post(ROOT, headers=owner, json=body).status_code == 422


def test_adaptive_jobs_enforce_turn_order_and_stale_answer(client, monkeypatch):
    api, engine = client
    monkeypatch.setattr(
        "career_copilot_backend.api.v1.routes.adaptive_interviews.provider_configured",
        lambda _: True,
    )
    owner = headers_for(api, "adaptive-jobs-owner@example.com")
    other = headers_for(api, "adaptive-jobs-other@example.com")
    item = api.post(
        ROOT,
        headers=owner,
        json={"role": "Engineer", "seniority": "mid", "skills": ["Swift"]},
    ).json()
    path = f"{ROOT}/{item['id']}"
    queued = api.post(f"{path}/next", headers=owner, json={})
    assert queued.status_code == 202
    assert (
        api.post(f"{path}/next", headers=owner, json={}).json()["id"]
        == queued.json()["id"]
    )
    assert (
        api.get(f"{path}/jobs/{queued.json()['id']}", headers=other).status_code == 404
    )
    sessions = sessionmaker(engine)
    generated = GeneratedTurn(
        prompt="What are actors?",
        topic="Swift",
        difficulty=3,
        follow_up_count=0,
        topics=("Swift",),
        covered_topics=("Swift",),
    )
    assert run_next_adaptive_job(sessions, lambda _: generated)
    assert (
        api.get(f"{path}/jobs/{queued.json()['id']}", headers=owner).json()["status"]
        == "completed"
    )
    turn = api.get(f"{path}/turns", headers=owner).json()["items"][0]
    assert api.post(f"{path}/next", headers=owner, json={}).status_code == 409

    answer_path = f"{path}/turns/{turn['id']}/answer"
    assert (
        api.put(answer_path, headers=other, json={"answer": "No access"}).status_code
        == 404
    )
    assert (
        api.put(
            answer_path, headers=owner, json={"answer": "Actors prevent data races."}
        ).status_code
        == 200
    )
    feedback_path = f"{path}/turns/{turn['id']}/evaluation"
    job = api.post(feedback_path, headers=owner, json={}).json()
    assert api.post(feedback_path, headers=owner, json={}).json()["id"] == job["id"]

    def change_answer(_):
        assert (
            api.put(
                answer_path, headers=owner, json={"answer": "Updated answer"}
            ).status_code
            == 200
        )
        return AdaptiveEvaluation.model_validate(evaluation_data())

    assert run_next_adaptive_job(sessions, change_answer)
    assert (
        api.get(f"{path}/jobs/{job['id']}", headers=owner).json()["status"] == "failed"
    )
    assert (
        api.get(f"{path}/turns", headers=owner).json()["items"][0]["evaluation"] is None
    )
    new_job = api.post(feedback_path, headers=owner, json={}).json()
    assert new_job["id"] != job["id"]
    assert run_next_adaptive_job(
        sessions, lambda _: AdaptiveEvaluation.model_validate(evaluation_data())
    )
    assert (
        api.get(f"{path}/turns", headers=owner).json()["items"][0]["evaluation"][
            "overall_score"
        ]
        == 3
    )
    assert api.post(f"{path}/next", headers=owner, json={}).status_code == 202
    assert api.get(f"{path}/report", headers=owner).status_code == 409
    assert api.post(f"{path}/complete", headers=other).status_code == 404
    completed = api.post(f"{path}/complete", headers=owner)
    assert completed.status_code == 200 and completed.json()["status"] == "completed"
    assert (
        api.post(f"{path}/complete", headers=owner).json()["state_version"]
        == completed.json()["state_version"]
    )
    report = api.get(f"{path}/report", headers=owner).json()
    assert (
        report["evaluated_answers"] == 1
        and report["topic_progress"][0]["topic"] == "Swift"
    )
    assert api.get(f"{path}/report", headers=other).status_code == 404
    assert api.post(f"{path}/next", headers=owner, json={}).status_code == 409


def test_adaptive_worker_generates_and_evaluates_without_resume(client, monkeypatch):
    api, engine = client
    monkeypatch.setattr(
        "career_copilot_backend.api.v1.routes.adaptive_interviews.provider_configured",
        lambda _: True,
    )
    owner = headers_for(api, "adaptive-real-handler@example.com")
    item = api.post(
        ROOT,
        headers=owner,
        json={
            "role": "iOS engineer",
            "seniority": "mid",
            "skills": ["Swift", "Networking"],
        },
    ).json()
    path = f"{ROOT}/{item['id']}"

    class FakeProvider:
        async def generate_structured(self, **kwargs):
            title = kwargs["output_schema"]["title"]
            if title == "AdaptiveQuestion":
                data = json.loads(kwargs["untrusted_text"])
                assert data["candidate_context"]["resume_skills"] == []
                if data["previous_questions"]:
                    assert data["previous_answer"] == "Actors help prevent data races."
                    assert data["previous_feedback"]["classification"] == "correct"
                    assert data["action"] == "deepen"
                    return json.dumps(
                        {"prompt": "How does actor reentrancy affect state?"}
                    )
                return json.dumps({"prompt": "How do actors prevent data races?"})
            return json.dumps(evaluation_data())

    sessions = sessionmaker(engine)
    provider = FakeProvider()
    first = api.post(f"{path}/next", headers=owner, json={}).json()
    assert run_next_adaptive_job(
        sessions, lambda job_id: process_adaptive_job(sessions, provider, job_id)
    )
    assert (
        api.get(f"{path}/jobs/{first['id']}", headers=owner).json()["status"]
        == "completed"
    )
    turn = api.get(f"{path}/turns", headers=owner).json()["items"][0]
    assert turn["topic"] == "Swift"
    assert (
        api.put(
            f"{path}/turns/{turn['id']}/answer",
            headers=owner,
            json={"answer": "Actors help prevent data races."},
        ).status_code
        == 200
    )
    job = api.post(
        f"{path}/turns/{turn['id']}/evaluation", headers=owner, json={}
    ).json()
    assert run_next_adaptive_job(
        sessions, lambda job_id: process_adaptive_job(sessions, provider, job_id)
    )
    assert (
        api.get(f"{path}/jobs/{job['id']}", headers=owner).json()["status"]
        == "completed"
    )
    assert api.get(f"{path}/turns", headers=owner).json()["items"][0]["evaluation"][
        "evidence"
    ] == ["prevent data races"]
    followup = api.post(f"{path}/next", headers=owner, json={}).json()
    assert run_next_adaptive_job(
        sessions, lambda job_id: process_adaptive_job(sessions, provider, job_id)
    )
    assert (
        api.get(f"{path}/jobs/{followup['id']}", headers=owner).json()["status"]
        == "completed"
    )
    turns = api.get(f"{path}/turns", headers=owner).json()["items"]
    assert (
        len(turns) == 2 and turns[1]["topic"] == "Swift" and turns[1]["difficulty"] == 4
    )


def test_skill_progress_requires_two_evaluations_and_is_private(client):
    api, engine = client
    owner = headers_for(api, "adaptive-progress-owner@example.com")
    other = headers_for(api, "adaptive-progress-other@example.com")
    item = api.post(
        ROOT, headers=owner, json={"role": "Engineer", "seniority": "mid"}
    ).json()
    session_id = UUID(item["id"])
    with Session(engine) as db:
        interview = db.get(AdaptiveInterviewSession, session_id)
        interview.status = "completed"
        db.add_all(
            [
                AdaptiveInterviewTurn(
                    session_id=session_id,
                    sequence=n,
                    topic="Swift",
                    difficulty=3,
                    question_type="technical",
                    prompt=f"Synthetic {n}?",
                    answer="prevent data races",
                    evaluation=evaluation_data(),
                )
                for n in (1, 2)
            ]
        )
        db.add(
            AdaptiveInterviewTurn(
                session_id=session_id,
                sequence=3,
                topic="SQL",
                difficulty=3,
                question_type="technical",
                prompt="Synthetic SQL?",
                answer="prevent data races",
                evaluation=evaluation_data(),
            )
        )
        db.commit()
    progress = api.get(
        "/api/v1/interviews/adaptive/skill-progress", headers=owner
    ).json()
    assert [
        (entry["topic"], entry["evidence_count"]) for entry in progress["items"]
    ] == [("Swift", 2)]
    assert (
        api.get("/api/v1/interviews/adaptive/skill-progress", headers=other).json()[
            "items"
        ]
        == []
    )


def test_report_compares_only_owned_comparable_sessions_with_evidence(client):
    api, engine = client
    owner = headers_for(api, "adaptive-report-owner@example.com")
    other = headers_for(api, "adaptive-report-other@example.com")
    first = api.post(
        ROOT, headers=owner, json={"role": "Engineer", "seniority": "mid"}
    ).json()
    second = api.post(
        ROOT, headers=owner, json={"role": "Engineer", "seniority": "mid"}
    ).json()
    unrelated = api.post(
        ROOT, headers=other, json={"role": "Engineer", "seniority": "mid"}
    ).json()
    now = datetime.now(UTC)
    with Session(engine) as db:
        for item, score, completed_at in [
            (first, 2, now - timedelta(days=1)),
            (second, 4, now),
            (unrelated, 0, now - timedelta(hours=1)),
        ]:
            session_id = UUID(item["id"])
            interview = db.get(AdaptiveInterviewSession, session_id)
            interview.status = "completed"
            interview.completed_at = completed_at
            db.add_all(
                [
                    AdaptiveInterviewTurn(
                        session_id=session_id,
                        sequence=n,
                        topic="Swift",
                        difficulty=3,
                        question_type="technical",
                        prompt=f"Synthetic {n}?",
                        answer="prevent data races",
                        evaluation=evaluation_data(score=score),
                    )
                    for n in (1, 2)
                ]
            )
        db.commit()
    report = api.get(f"{ROOT}/{second['id']}/report", headers=owner).json()
    assert report["previous_average_score"] == 2
    assert report["score_change"] == 2
    assert report["strongest_topics"] == ["Swift"]


def test_question_context_minimizes_resume_and_separates_user_skills(
    client, monkeypatch
):
    api, engine = client
    monkeypatch.setattr(
        "career_copilot_backend.api.v1.routes.adaptive_interviews.provider_configured",
        lambda _: True,
    )
    owner = headers_for(api, "adaptive-profile-owner@example.com")
    resume = api.post(
        "/api/v1/resumes",
        headers=owner,
        files={"file": ("synthetic.pdf", make_pdf(True), "application/pdf")},
    ).json()
    synthetic = "Private marker 49383. Synthetic project using SwiftUI and Combine."
    assert (
        api.patch(
            f"/api/v1/resumes/{resume['id']}", headers=owner, json={"text": synthetic}
        ).status_code
        == 200
    )
    item = api.post(
        ROOT,
        headers=owner,
        json={
            "role": "iOS engineer",
            "seniority": "mid",
            "resume_id": resume["id"],
            "skills": ["Kotlin"],
        },
    ).json()
    path = f"{ROOT}/{item['id']}"
    queued = api.post(f"{path}/next", headers=owner, json={}).json()

    class FakeProvider:
        async def generate_structured(self, **kwargs):
            data = json.loads(kwargs["untrusted_text"])
            assert "Private marker 49383" not in kwargs["untrusted_text"]
            assert {
                item["name"] for item in data["candidate_context"]["resume_skills"]
            } == {"SwiftUI", "Combine"}
            assert data["candidate_context"]["selected_skills"] == ["Kotlin"]
            assert data["candidate_context"]["resume_context"] == [
                "Synthetic project using SwiftUI and Combine."
            ]
            return json.dumps(
                {"prompt": "How would you approach Kotlin for this role?"}
            )

    sessions = sessionmaker(engine)
    assert run_next_adaptive_job(
        sessions, lambda job_id: process_adaptive_job(sessions, FakeProvider(), job_id)
    )
    assert (
        api.get(f"{path}/jobs/{queued['id']}", headers=owner).json()["status"]
        == "completed"
    )


def test_failed_job_needs_explicit_owned_retry(client, monkeypatch):
    api, engine = client
    monkeypatch.setattr(
        "career_copilot_backend.api.v1.routes.adaptive_interviews.provider_configured",
        lambda _: True,
    )
    owner = headers_for(api, "adaptive-retry-owner@example.com")
    other = headers_for(api, "adaptive-retry-other@example.com")
    item = api.post(
        ROOT, headers=owner, json={"role": "Engineer", "seniority": "mid"}
    ).json()
    path = f"{ROOT}/{item['id']}"
    queued = api.post(f"{path}/next", headers=owner, json={}).json()
    sessions = sessionmaker(engine)

    def fail(_):
        raise ProviderError("Synthetic provider failure", code="rate_limited")

    assert run_next_adaptive_job(sessions, fail)
    status = api.get(f"{path}/jobs/{queued['id']}", headers=owner).json()
    assert status["status"] == "failed" and status["error_code"] == "rate_limited"
    assert not run_next_adaptive_job(sessions, fail)
    retry_path = f"{path}/jobs/{queued['id']}/retry"
    assert api.post(retry_path, headers=other, json={}).status_code == 404
    assert api.post(retry_path, headers=owner, json={}).json()["status"] == "queued"
    assert api.post(retry_path, headers=owner, json={}).status_code == 409


def test_reviewed_reference_is_selected_and_attributed(client, monkeypatch):
    api, engine = client
    monkeypatch.setattr(
        "career_copilot_backend.api.v1.routes.adaptive_interviews.provider_configured",
        lambda _: True,
    )
    monkeypatch.setattr(settings, "reviewed_technical_source_ids", "synthetic")
    owner = headers_for(api, "adaptive-reference-owner@example.com")
    item = api.post(
        ROOT, headers=owner, json={"role": "iOS engineer", "seniority": "mid"}
    ).json()
    path = f"{ROOT}/{item['id']}"
    source = Source(
        id="synthetic",
        title="Synthetic reference",
        origin="Test",
        text="Actors isolate mutable state.",
        kind="technical_reference",
        roles=["ios"],
        topics=["swift"],
        version="2",
    )
    monkeypatch.setattr(
        "career_copilot_backend.services.adaptive_jobs.load_corpus", lambda: [source]
    )

    class FakeEmbedder:
        def __init__(self, _):
            pass

        def embed(self, texts, *, query=False):
            return [[0.1] * 768]

    monkeypatch.setattr(
        "career_copilot_backend.services.adaptive_jobs.OllamaEmbedder", FakeEmbedder
    )
    monkeypatch.setattr(
        "career_copilot_backend.services.adaptive_jobs.retrieve",
        lambda db, vector, **kwargs: [
            SimpleNamespace(
                id="synthetic:0",
                source_id="synthetic",
                title=source.title,
                origin=source.origin,
                content=source.text,
            )
        ],
    )
    with Session(engine) as db:
        turn = AdaptiveInterviewTurn(
            session_id=UUID(item["id"]),
            sequence=1,
            topic="Swift",
            difficulty=3,
            question_type="technical",
            prompt="What do actors protect?",
            answer="Actors help prevent data races.",
            answer_revision=1,
        )
        db.add(turn)
        db.commit()
        turn_id = turn.id
    job = api.post(f"{path}/turns/{turn_id}/evaluation", headers=owner, json={}).json()

    class FakeProvider:
        async def generate_structured(self, **kwargs):
            data = json.loads(kwargs["untrusted_text"])
            assert data["reference_excerpts"][0]["id"] == "synthetic:0"
            result = evaluation_data()
            result["reference_ids"] = ["synthetic:0"]
            return json.dumps(result)

    sessions = sessionmaker(engine)
    assert run_next_adaptive_job(
        sessions, lambda job_id: process_adaptive_job(sessions, FakeProvider(), job_id)
    )
    assert (
        api.get(f"{path}/jobs/{job['id']}", headers=owner).json()["status"]
        == "completed"
    )
    evaluation = api.get(f"{path}/turns", headers=owner).json()["items"][0][
        "evaluation"
    ]
    assert evaluation["references"][0]["title"] == "Synthetic reference"
    assert evaluation["reference_versions"] == {"synthetic:0": "2"}


def test_behavioral_evaluation_uses_behavioral_rubric_without_retrieval(
    client, monkeypatch
):
    api, engine = client
    monkeypatch.setattr(
        "career_copilot_backend.api.v1.routes.adaptive_interviews.provider_configured",
        lambda _: True,
    )
    monkeypatch.setattr(settings, "reviewed_technical_source_ids", "synthetic")
    owner = headers_for(api, "adaptive-behavioral@example.com")
    item = api.post(
        ROOT,
        headers=owner,
        json={"role": "Engineer", "seniority": "mid", "interview_type": "behavioral"},
    ).json()
    path = f"{ROOT}/{item['id']}"
    with Session(engine) as db:
        turn = AdaptiveInterviewTurn(
            session_id=UUID(item["id"]),
            sequence=1,
            topic="Collaboration",
            difficulty=3,
            question_type="behavioral",
            prompt="Describe collaboration.",
            answer="We helped prevent data races.",
            answer_revision=1,
        )
        db.add(turn)
        db.commit()
        turn_id = turn.id
    job = api.post(f"{path}/turns/{turn_id}/evaluation", headers=owner, json={}).json()

    class FakeProvider:
        async def generate_structured(self, **kwargs):
            data = json.loads(kwargs["untrusted_text"])
            assert (
                data["question_type"] == "behavioral"
                and data["reference_excerpts"] == []
            )
            return json.dumps(evaluation_data())

    sessions = sessionmaker(engine)
    assert run_next_adaptive_job(
        sessions, lambda job_id: process_adaptive_job(sessions, FakeProvider(), job_id)
    )
    assert (
        api.get(f"{path}/jobs/{job['id']}", headers=owner).json()["status"]
        == "completed"
    )
