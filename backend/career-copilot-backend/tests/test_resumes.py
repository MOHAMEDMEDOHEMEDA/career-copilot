import test_auth
from test_pdf import make_pdf

from career_copilot_backend.core.config import settings

client = test_auth.client


def test_resume_crud_and_isolation(client) -> None:
    test_client, _ = client
    headers = []
    for email in ("owner@example.com", "other@example.com"):
        credentials = {"email": email, "password": "secure-password"}
        assert (
            test_client.post("/api/v1/auth/register", json=credentials).status_code
            == 201
        )
        token = test_client.post("/api/v1/auth/login", json=credentials).json()[
            "access_token"
        ]
        headers.append({"Authorization": f"Bearer {token}"})
    uploaded = test_client.post(
        "/api/v1/resumes",
        headers=headers[0],
        files={"file": ("resume.pdf", make_pdf(True), "application/pdf")},
    )
    assert uploaded.status_code == 201
    resume_id = uploaded.json()["id"]
    assert "Synthetic resume" in uploaded.json()["text"]
    assert (
        len(test_client.get("/api/v1/resumes", headers=headers[0]).json()["items"]) == 1
    )
    assert test_client.get("/api/v1/resumes", headers=headers[1]).json()["items"] == []
    for method in ("get", "patch", "delete"):
        response = test_client.request(
            method,
            f"/api/v1/resumes/{resume_id}",
            headers=headers[1],
            json={"text": "changed"} if method == "patch" else None,
        )
        assert response.status_code == 404
    assert (
        test_client.patch(
            f"/api/v1/resumes/{resume_id}",
            headers=headers[0],
            json={"text": "Updated resume"},
        ).json()["text"]
        == "Updated resume"
    )
    assert (
        test_client.delete(
            f"/api/v1/resumes/{resume_id}", headers=headers[0]
        ).status_code
        == 204
    )
    assert (
        test_client.get(f"/api/v1/resumes/{resume_id}", headers=headers[0]).status_code
        == 404
    )


def test_upload_rejects_invalid_and_scanned_pdfs(client) -> None:
    test_client, _ = client
    credentials = {"email": "owner@example.com", "password": "secure-password"}
    test_client.post("/api/v1/auth/register", json=credentials)
    token = test_client.post("/api/v1/auth/login", json=credentials).json()[
        "access_token"
    ]
    headers = {"Authorization": f"Bearer {token}"}
    invalid = test_client.post(
        "/api/v1/resumes",
        headers=headers,
        files={"file": ("resume.pdf", b"broken", "application/pdf")},
    )
    assert invalid.status_code == 400
    scanned = test_client.post(
        "/api/v1/resumes",
        headers=headers,
        files={"file": ("resume.pdf", make_pdf(False), "application/pdf")},
    )
    assert scanned.status_code == 400
    assert "OCR" in scanned.json()["error"]["message"]


def test_upload_rate_limit_is_per_user(client, monkeypatch) -> None:
    test_client, _ = client
    monkeypatch.setattr(settings, "upload_limit_per_hour", 1)
    authorization = []
    for email in ("first@example.com", "second@example.com"):
        credentials = {"email": email, "password": "secure-password"}
        test_client.post("/api/v1/auth/register", json=credentials)
        token = test_client.post("/api/v1/auth/login", json=credentials).json()[
            "access_token"
        ]
        authorization.append({"Authorization": f"Bearer {token}"})
    for index in (0, 1):
        response = test_client.post(
            "/api/v1/resumes",
            headers=authorization[index],
            files={"file": ("resume.pdf", make_pdf(True), "application/pdf")},
        )
        assert response.status_code == 201
    limited = test_client.post(
        "/api/v1/resumes",
        headers=authorization[0],
        files={"file": ("resume.pdf", make_pdf(True), "application/pdf")},
    )
    assert limited.status_code == 429
    assert limited.headers["retry-after"] == "3600"
