from fastapi.testclient import TestClient

from career_copilot_backend.main import app


def test_missing_route_uses_error_envelope() -> None:
    response = TestClient(app).get("/missing")

    assert response.status_code == 404
    assert response.json() == {"error": {"code": "http_error", "message": "Not Found"}}
