import pytest
import test_auth
from sqlalchemy import select
from sqlalchemy.orm import Session

from career_copilot_backend.api.v1.routes.auth import google_verifier
from career_copilot_backend.core.config import settings
from career_copilot_backend.main import app
from career_copilot_backend.models import ExternalIdentity, User
from career_copilot_backend.services.google_auth import (
    GoogleIdentity,
    InvalidGoogleToken,
    verify_google_identity,
)

client = test_auth.client


def test_google_new_user_and_existing_identity(client):
    test_client, engine = client
    app.dependency_overrides[google_verifier] = lambda: (
        lambda token: GoogleIdentity("google-subject", "google@example.com")
    )
    try:
        first = test_client.post("/api/v1/auth/google", json={"id_token": "synthetic"})
        second = test_client.post("/api/v1/auth/google", json={"id_token": "synthetic"})
        assert first.status_code == second.status_code == 200
        profile = test_client.patch(
            "/api/v1/auth/me/name",
            headers={"Authorization": f"Bearer {first.json()['access_token']}"},
            json={"display_name": "Google User"},
        )
        assert profile.status_code == 200
        assert profile.json()["display_name"] == "Google User"
        with Session(engine) as session:
            user = session.scalar(
                select(User).where(User.email == "google@example.com")
            )
            assert user is not None and user.password_hash is None
            assert len(session.scalars(select(ExternalIdentity)).all()) == 1
        assert (
            test_client.post(
                "/api/v1/auth/login",
                json={"email": "google@example.com", "password": "some-password"},
            ).status_code
            == 401
        )
    finally:
        app.dependency_overrides.pop(google_verifier, None)


def test_existing_email_requires_explicit_authenticated_link(client):
    test_client, _ = client
    credentials = {"email": "existing@example.com", "password": "secure-password"}
    test_client.post("/api/v1/auth/register", json=credentials)
    app.dependency_overrides[google_verifier] = lambda: (
        lambda token: GoogleIdentity("google-subject", "existing@example.com")
    )
    try:
        assert (
            test_client.post(
                "/api/v1/auth/google", json={"id_token": "synthetic"}
            ).status_code
            == 409
        )
        assert (
            test_client.post(
                "/api/v1/auth/google/link", json={"id_token": "synthetic"}
            ).status_code
            == 401
        )
        access = test_client.post("/api/v1/auth/login", json=credentials).json()[
            "access_token"
        ]
        response = test_client.post(
            "/api/v1/auth/google/link",
            json={"id_token": "synthetic"},
            headers={"Authorization": f"Bearer {access}"},
        )
        assert response.status_code == 204
        assert (
            test_client.post(
                "/api/v1/auth/google", json={"id_token": "synthetic"}
            ).status_code
            == 200
        )
    finally:
        app.dependency_overrides.pop(google_verifier, None)


def test_invalid_google_token_rejected(client):
    test_client, _ = client

    def reject(token):
        raise InvalidGoogleToken

    app.dependency_overrides[google_verifier] = lambda: reject
    try:
        assert (
            test_client.post(
                "/api/v1/auth/google", json={"id_token": "invalid"}
            ).status_code
            == 401
        )
    finally:
        app.dependency_overrides.pop(google_verifier, None)


def test_google_verifier_checks_audience_and_verified_email(monkeypatch):
    monkeypatch.setattr(settings, "google_server_client_id", "expected-client-id")
    seen = []

    def verify(token, request, audience):
        seen.append(audience)
        return {
            "sub": "subject",
            "email": "person@example.com",
            "email_verified": False,
        }

    monkeypatch.setattr(
        "career_copilot_backend.services.google_auth.id_token.verify_oauth2_token",
        verify,
    )
    with pytest.raises(InvalidGoogleToken):
        verify_google_identity("synthetic")
    assert seen == ["expected-client-id"]


@pytest.mark.parametrize(
    "reason", ["Token expired", "Token has wrong audience", "Bad signature"]
)
def test_google_verification_failures_are_rejected(monkeypatch, reason):
    monkeypatch.setattr(settings, "google_server_client_id", "expected-client-id")

    def verify(token, request, audience):
        raise ValueError(reason)

    monkeypatch.setattr(
        "career_copilot_backend.services.google_auth.id_token.verify_oauth2_token",
        verify,
    )
    with pytest.raises(InvalidGoogleToken):
        verify_google_identity("synthetic")


def test_google_identity_cannot_be_linked_to_another_user(client):
    test_client, _ = client
    app.dependency_overrides[google_verifier] = lambda: (
        lambda token: GoogleIdentity("google-subject", "google@example.com")
    )
    try:
        assert (
            test_client.post(
                "/api/v1/auth/google", json={"id_token": "synthetic"}
            ).status_code
            == 200
        )
        credentials = {"email": "other@example.com", "password": "secure-password"}
        test_client.post("/api/v1/auth/register", json=credentials)
        token = test_client.post("/api/v1/auth/login", json=credentials).json()[
            "access_token"
        ]
        response = test_client.post(
            "/api/v1/auth/google/link",
            json={"id_token": "synthetic"},
            headers={"Authorization": f"Bearer {token}"},
        )
        assert response.status_code == 409
    finally:
        app.dependency_overrides.pop(google_verifier, None)
