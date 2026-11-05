from fastapi.testclient import TestClient

from career_copilot_backend.main import app


def test_missing_route_uses_error_envelope() -> None:
    response = TestClient(app).get("/missing")

    assert response.status_code == 404
    assert response.json() == {"error": {"code": "http_error", "message": "Not Found"}}


def test_invalid_login_reports_safe_specific_errors() -> None:
    response = TestClient(app).post(
        "/api/v1/auth/login", json={"email": "not-an-email", "password": "secret"}
    )

    assert response.status_code == 422
    assert response.json()["error"]["message"] == (
        "Enter a valid email address. Password must be between 8 and 128 characters."
    )
    assert "secret" not in response.text
    assert "not-an-email" not in response.text
