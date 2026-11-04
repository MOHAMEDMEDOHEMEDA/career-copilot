import test_auth
from sqlalchemy import select
from sqlalchemy.orm import Session, sessionmaker
from test_pdf import make_pdf

from career_copilot_backend.models import Job, User
from career_copilot_backend.services.jobs import create_job, run_next_job

client = test_auth.client


def test_job_status_is_user_owned(client) -> None:
    test_client, engine = client
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
    from uuid import UUID

    with Session(engine) as session:
        owner = session.scalar(select(User).where(User.email == "owner@example.com"))
        assert owner is not None
        job = create_job(session, owner.id, UUID(resume["id"]), "resume_analysis")
        job_id = str(job.id)
    response = test_client.get(f"/api/v1/jobs/{job_id}", headers=headers[0])
    assert response.status_code == 200
    assert response.json()["status"] == "queued"
    assert (
        test_client.get(f"/api/v1/jobs/{job_id}", headers=headers[1]).status_code == 404
    )


def test_worker_completes_and_marks_expired_jobs_failed(client) -> None:
    from datetime import UTC, datetime, timedelta
    from uuid import UUID, uuid4

    test_client, engine = client
    credentials = {"email": "worker@example.com", "password": "secure-password"}
    test_client.post("/api/v1/auth/register", json=credentials)
    token = test_client.post("/api/v1/auth/login", json=credentials).json()[
        "access_token"
    ]
    resume = test_client.post(
        "/api/v1/resumes",
        headers={"Authorization": f"Bearer {token}"},
        files={"file": ("resume.pdf", make_pdf(True), "application/pdf")},
    ).json()
    with Session(engine) as session:
        owner = session.scalar(select(User).where(User.email == credentials["email"]))
        assert owner is not None
        queued = create_job(session, owner.id, UUID(resume["id"]), "test")
        queued_id = queued.id
        expired = create_job(session, owner.id, UUID(resume["id"]), "test")
        expired_id = expired.id
        expired.status = "running"
        expired.lease_id = uuid4()
        expired.lease_expires_at = datetime.now(UTC) - timedelta(seconds=1)
        session.commit()
    handled = []
    assert run_next_job(
        sessionmaker(bind=engine, expire_on_commit=False), {"test": handled.append}
    )
    assert handled == [queued_id]
    with Session(engine) as session:
        assert session.get(Job, queued_id).status == "completed"
        assert session.get(Job, expired_id).status == "failed"
