import test_auth
from pydantic import SecretStr
from sqlalchemy.orm import sessionmaker
from test_analysis import FakeProvider, valid_output
from test_pdf import make_pdf

from career_copilot_backend.core.config import settings
from career_copilot_backend.services.analysis_jobs import process_analysis
from career_copilot_backend.services.jobs import run_next_job

client = test_auth.client


def test_analysis_job_flow_and_isolation(client, monkeypatch):
    test_client, engine = client
    monkeypatch.setattr(settings, "openrouter_api_key", SecretStr("fake-key"))
    headers = []
    for email in ("owner@example.com", "other@example.com"):
        credentials = {"email": email, "password": "secure-password"}
        test_client.post("/api/v1/auth/register", json=credentials)
        token = test_client.post("/api/v1/auth/login", json=credentials).json()[
            "access_token"
        ]
        headers.append({"Authorization": f"Bearer {token}"})
    resume = test_client.post(
        "/api/v1/resumes",
        headers=headers[0],
        files={"file": ("resume.pdf", make_pdf(True), "application/pdf")},
    ).json()
    body = {"resume_id": resume["id"]}
    assert (
        test_client.post(
            "/api/v1/resume-analysis", headers=headers[1], json=body
        ).status_code
        == 404
    )
    queued = test_client.post("/api/v1/resume-analysis", headers=headers[0], json=body)
    assert queued.status_code == 202
    assert queued.json()["status"] == "queued"
    job_id = queued.json()["id"]
    assert (
        test_client.get(f"/api/v1/jobs/{job_id}", headers=headers[1]).status_code == 404
    )
    sessions = sessionmaker(bind=engine, expire_on_commit=False)
    provider = FakeProvider(valid_output())
    assert run_next_job(
        sessions,
        {
            "resume_analysis": lambda job_id: process_analysis(
                sessions, provider, job_id
            )
        },
    )
    completed = test_client.get(f"/api/v1/jobs/{job_id}", headers=headers[0]).json()
    assert completed["status"] == "completed"
    assert completed["result"]["summary"] == "Developer"
    assert len(provider.calls) == 1
    assert (
        test_client.delete(
            f"/api/v1/resumes/{resume['id']}", headers=headers[0]
        ).status_code
        == 204
    )


def test_malformed_analysis_marks_job_failed_without_result(client, monkeypatch):
    test_client, engine = client
    monkeypatch.setattr(settings, "openrouter_api_key", SecretStr("fake-key"))
    credentials = {"email": "owner@example.com", "password": "secure-password"}
    test_client.post("/api/v1/auth/register", json=credentials)
    token = test_client.post("/api/v1/auth/login", json=credentials).json()[
        "access_token"
    ]
    headers = {"Authorization": f"Bearer {token}"}
    resume = test_client.post(
        "/api/v1/resumes",
        headers=headers,
        files={"file": ("resume.pdf", make_pdf(True), "application/pdf")},
    ).json()
    job = test_client.post(
        "/api/v1/resume-analysis", headers=headers, json={"resume_id": resume["id"]}
    ).json()
    sessions = sessionmaker(bind=engine, expire_on_commit=False)
    provider = FakeProvider("not valid json")
    assert run_next_job(
        sessions,
        {
            "resume_analysis": lambda job_id: process_analysis(
                sessions, provider, job_id
            )
        },
    )
    result = test_client.get(f"/api/v1/jobs/{job['id']}", headers=headers).json()
    assert result["status"] == "failed"
    assert result["result"] is None
    assert len(provider.calls) == 1
