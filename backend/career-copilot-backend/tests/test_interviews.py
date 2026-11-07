from uuid import UUID

import test_auth
from sqlalchemy import func, select
from sqlalchemy.orm import Session, sessionmaker
from test_chat import headers_for
from test_pdf import make_pdf

from career_copilot_backend.models import InterviewQuestion
from career_copilot_backend.schemas.interview import (
    InterviewFeedback,
    InterviewQuestions,
)
from career_copilot_backend.services.interview_jobs import run_next_interview_job

client = test_auth.client
ROOT = "/api/v1/interviews/sessions"


def test_interview_privacy_and_answer_lifecycle(client):
    api, engine = client
    owner = headers_for(api, "interview-owner@example.com")
    other = headers_for(api, "interview-other@example.com")
    resume = api.post(
        "/api/v1/resumes",
        headers=owner,
        files={"file": ("synthetic.pdf", make_pdf(True), "application/pdf")},
    )
    assert resume.status_code == 201
    body = {
        "resume_id": resume.json()["id"],
        "job_description": "Synthetic software role",
    }
    assert api.get(ROOT).status_code == 401
    assert api.post(ROOT, headers=other, json=body).status_code == 404
    created = api.post(ROOT, headers=owner, json=body)
    assert created.status_code == 201
    assert created.json()["status"] == "draft"
    interview_id = created.json()["id"]
    path = f"{ROOT}/{interview_id}"
    assert api.get(ROOT, headers=other).json()["items"] == []
    assert api.get(path, headers=other).status_code == 404
    assert api.get(f"{path}/questions", headers=other).status_code == 404
    assert api.delete(path, headers=other).status_code == 404
    with Session(engine) as db:
        question = InterviewQuestion(
            session_id=UUID(interview_id),
            sequence=1,
            prompt="Describe a synthetic project.",
            feedback={"old": "feedback"},
        )
        db.add(question)
        db.commit()
        question_id = question.id
    answer_path = f"{path}/questions/{question_id}/answer"
    assert (
        api.put(answer_path, headers=other, json={"answer": "No access"}).status_code
        == 404
    )
    assert (
        api.put(answer_path, headers=owner, json={"answer": "   "}).status_code == 422
    )
    assert (
        api.put(answer_path, headers=owner, json={"answer": "x" * 4001}).status_code
        == 422
    )
    saved = api.put(
        answer_path, headers=owner, json={"answer": "I built a sample project."}
    )
    assert saved.status_code == 200
    assert saved.json()["feedback"] is None
    assert (
        api.get(f"{path}/questions", headers=owner).json()["items"][0]["answer"]
        == "I built a sample project."
    )
    with Session(engine) as db:
        assert db.get(InterviewQuestion, question_id).answer_revision == 1
    assert api.delete(path, headers=owner).status_code == 204
    with Session(engine) as db:
        assert db.scalar(select(func.count()).select_from(InterviewQuestion)) == 0


def test_interview_input_validation(client):
    api, _ = client
    owner = headers_for(api, "interview-validation@example.com")
    body = {"resume_id": "00000000-0000-0000-0000-000000000001", "job_description": " "}
    assert api.post(ROOT, headers=owner, json=body).status_code == 422
    body["job_description"] = "x" * 20001
    assert api.post(ROOT, headers=owner, json=body).status_code == 422
    assert api.get(f"{ROOT}?limit=101", headers=owner).status_code == 422


def test_worker_generates_and_rejects_stale_feedback(client, monkeypatch):
    api, engine = client
    monkeypatch.setattr(
        "career_copilot_backend.api.v1.routes.interviews.provider_configured",
        lambda _: True,
    )
    owner = headers_for(api, "interview-worker@example.com")
    other = headers_for(api, "interview-worker-other@example.com")
    resume = api.post(
        "/api/v1/resumes",
        headers=owner,
        files={"file": ("synthetic.pdf", make_pdf(True), "application/pdf")},
    ).json()
    interview = api.post(
        ROOT,
        headers=owner,
        json={"resume_id": resume["id"], "job_description": "Software role"},
    ).json()
    path = f"{ROOT}/{interview['id']}"
    generation = api.post(f"{path}/generation", headers=owner, json={}).json()
    assert (
        api.post(f"{path}/generation", headers=owner, json={}).json()["id"]
        == generation["id"]
    )
    assert api.get(f"{path}/jobs/{generation['id']}", headers=other).status_code == 404
    sessions = sessionmaker(engine)
    questions = InterviewQuestions.model_validate(
        {"questions": [{"prompt": f"Question {i}?"} for i in range(3)]}
    )
    assert run_next_interview_job(sessions, lambda _: questions)
    assert (
        api.get(f"{path}/jobs/{generation['id']}", headers=owner).json()["status"]
        == "completed"
    )
    items = api.get(f"{path}/questions", headers=owner).json()["items"]
    assert len(items) == 3
    answer_path = f"{path}/questions/{items[0]['id']}/answer"
    assert (
        api.put(answer_path, headers=owner, json={"answer": "First answer"}).status_code
        == 200
    )
    feedback_path = f"{path}/questions/{items[0]['id']}/feedback"
    job = api.post(feedback_path, headers=owner, json={}).json()
    criterion = {"rating": "developing", "explanation": "Add details."}
    feedback = InterviewFeedback.model_validate(
        {
            **{
                key: criterion
                for key in ("correctness", "completeness", "relevance", "clarity")
            },
            "strengths": [],
            "improvements": ["Add detail"],
            "example_answer": "[Your example]",
        }
    )

    def change_answer(_):
        assert (
            api.put(
                answer_path, headers=owner, json={"answer": "Updated answer"}
            ).status_code
            == 200
        )
        return feedback

    assert run_next_interview_job(sessions, change_answer)
    result = api.get(f"{path}/jobs/{job['id']}", headers=owner).json()
    assert result["status"] == "failed" and result["error_code"] == "stale_answer"
    assert (
        api.get(f"{path}/questions", headers=owner).json()["items"][0]["feedback"]
        is None
    )
    assert (
        api.post(f"{path}/jobs/{job['id']}/retry", headers=owner, json={}).status_code
        == 409
    )
    next_job = api.post(feedback_path, headers=owner, json={}).json()
    assert next_job["id"] != job["id"]
    assert run_next_interview_job(sessions, lambda _: feedback)
    assert (
        api.get(f"{path}/questions", headers=owner).json()["items"][0]["feedback"][
            "clarity"
        ]["rating"]
        == "developing"
    )
