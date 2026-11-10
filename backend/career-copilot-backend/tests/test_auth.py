from datetime import UTC, datetime, timedelta

import jwt
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from career_copilot_backend.core.config import settings
from career_copilot_backend.core.database import Base, get_db
from career_copilot_backend.main import app
from career_copilot_backend.models import RefreshToken, User


@pytest.fixture
def client(monkeypatch: pytest.MonkeyPatch):
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    Base.metadata.create_all(engine)
    monkeypatch.setattr(
        settings, "jwt_secret", "test-secret-that-is-at-least-32-characters"
    )

    def get_test_db():
        with Session(engine) as session:
            yield session

    app.dependency_overrides[get_db] = get_test_db
    with TestClient(app) as test_client:
        yield test_client, engine
    app.dependency_overrides.pop(get_db, None)
    engine.dispose()


def test_register_and_login(client) -> None:
    test_client, engine = client
    credentials = {"email": "person@example.com", "password": "correct-password"}
    response = test_client.post("/api/v1/auth/register", json=credentials)
    assert response.status_code == 201
    assert response.json()["email"] == credentials["email"]
    assert "password_hash" not in response.json()
    with Session(engine) as session:
        user = session.scalar(select(User))
        assert user is not None
        assert user.password_hash.startswith("$argon2")
        assert user.password_hash != credentials["password"]
    response = test_client.post("/api/v1/auth/login", json=credentials)
    assert response.status_code == 200
    payload = jwt.decode(
        response.json()["access_token"], settings.jwt_secret, algorithms=["HS256"]
    )
    assert payload["sub"] == str(user.id)
    assert payload["exp"] > payload["iat"]


def test_duplicate_and_wrong_password(client) -> None:
    test_client, _ = client
    credentials = {"email": "person@example.com", "password": "correct-password"}
    assert (
        test_client.post("/api/v1/auth/register", json=credentials).status_code == 201
    )
    assert (
        test_client.post("/api/v1/auth/register", json=credentials).status_code == 409
    )
    credentials["password"] = "incorrect-password"
    assert test_client.post("/api/v1/auth/login", json=credentials).status_code == 401


def test_refresh_rotation_logout_and_profile(client) -> None:
    test_client, _ = client
    credentials = {"email": "person@example.com", "password": "correct-password"}
    test_client.post("/api/v1/auth/register", json=credentials)
    tokens = test_client.post("/api/v1/auth/login", json=credentials).json()
    profile = test_client.get(
        "/api/v1/auth/me", headers={"Authorization": f"Bearer {tokens['access_token']}"}
    )
    assert profile.status_code == 200
    assert profile.json()["email"] == credentials["email"]
    assert profile.headers["x-request-id"]
    updated = test_client.patch(
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
        json={"email": "updated@example.com", "password": credentials["password"]},
    )
    assert updated.status_code == 200
    assert updated.json()["email"] == "updated@example.com"
    rotated = test_client.post(
        "/api/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]}
    )
    assert rotated.status_code == 200
    assert (
        test_client.post(
            "/api/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]}
        ).status_code
        == 401
    )
    new_token = rotated.json()["refresh_token"]
    assert new_token != tokens["refresh_token"]
    assert (
        test_client.post(
            "/api/v1/auth/logout", json={"refresh_token": new_token}
        ).status_code
        == 204
    )
    assert (
        test_client.post(
            "/api/v1/auth/refresh", json={"refresh_token": new_token}
        ).status_code
        == 401
    )


def test_expired_tokens_rejected(client) -> None:
    test_client, engine = client
    credentials = {"email": "person@example.com", "password": "correct-password"}
    user_id = test_client.post("/api/v1/auth/register", json=credentials).json()["id"]
    tokens = test_client.post("/api/v1/auth/login", json=credentials).json()
    with Session(engine) as session:
        refresh_token = session.scalar(select(RefreshToken))
        assert refresh_token is not None
        refresh_token.expires_at = datetime.now(UTC) - timedelta(seconds=1)
        session.commit()
    assert (
        test_client.post(
            "/api/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]}
        ).status_code
        == 401
    )
    expired = jwt.encode(
        {
            "sub": user_id,
            "iat": datetime.now(UTC) - timedelta(minutes=2),
            "exp": datetime.now(UTC) - timedelta(minutes=1),
        },
        settings.jwt_secret,
        algorithm="HS256",
    )
    assert (
        test_client.get(
            "/api/v1/auth/me", headers={"Authorization": f"Bearer {expired}"}
        ).status_code
        == 401
    )


def test_display_name_requires_auth_and_is_owned(client) -> None:
    test_client, _ = client
    first = {"email": "first@example.com", "password": "correct-password"}
    second = {"email": "second@example.com", "password": "correct-password"}
    for credentials in (first, second):
        assert test_client.post("/api/v1/auth/register", json=credentials).status_code == 201
    tokens = [test_client.post("/api/v1/auth/login", json=item).json()["access_token"] for item in (first, second)]
    headers = [{"Authorization": f"Bearer {token}"} for token in tokens]
    assert test_client.patch("/api/v1/auth/me/name", json={"display_name": "Name"}).status_code == 401
    result = test_client.patch("/api/v1/auth/me/name", headers=headers[0], json={"display_name": "  محمد علي  "})
    assert result.status_code == 200
    assert result.json()["display_name"] == "محمد علي"
    assert test_client.get("/api/v1/auth/me", headers=headers[0]).json()["display_name"] == "محمد علي"
    assert test_client.get("/api/v1/auth/me", headers=headers[1]).json()["display_name"] is None
    for value in (" ", "a" * 101, "name\nother"):
        assert test_client.patch("/api/v1/auth/me/name", headers=headers[0], json={"display_name": value}).status_code == 422
    assert test_client.patch("/api/v1/auth/me/name", headers=headers[0], json={"display_name": "Name", "email": second["email"]}).status_code == 422
