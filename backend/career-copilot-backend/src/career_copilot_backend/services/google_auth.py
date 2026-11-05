from dataclasses import dataclass

from google.auth.exceptions import GoogleAuthError, TransportError
from google.auth.transport.requests import Request
from google.oauth2 import id_token
from pydantic import EmailStr, TypeAdapter, ValidationError
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from career_copilot_backend.core.config import settings
from career_copilot_backend.models import ExternalIdentity, User


@dataclass(frozen=True)
class GoogleIdentity:
    subject: str
    email: str


class InvalidGoogleToken(Exception):
    pass


class GoogleAuthUnavailable(Exception):
    pass


class IdentityConflict(Exception):
    pass


def verify_google_identity(token: str) -> GoogleIdentity:
    if not settings.google_server_client_id:
        raise GoogleAuthUnavailable("Google authentication is not configured")
    request = Request()

    def bounded_request(*args, **kwargs):
        kwargs["timeout"] = 5
        return request(*args, **kwargs)

    try:
        claims = id_token.verify_oauth2_token(
            token, bounded_request, settings.google_server_client_id
        )
        subject = claims.get("sub")
        if (
            not isinstance(subject, str)
            or not subject
            or len(subject) > 255
            or claims.get("email_verified") is not True
        ):
            raise InvalidGoogleToken
        email = TypeAdapter(EmailStr).validate_python(claims.get("email"))
        return GoogleIdentity(subject=subject, email=email.lower())
    except TransportError as exc:
        raise GoogleAuthUnavailable(
            "Google authentication is temporarily unavailable"
        ) from exc
    except (ValueError, GoogleAuthError, ValidationError) as exc:
        raise InvalidGoogleToken from exc


def google_user(session: Session, identity: GoogleIdentity) -> User:
    linked = session.scalar(
        select(ExternalIdentity).where(
            ExternalIdentity.provider == "google",
            ExternalIdentity.subject == identity.subject,
        )
    )
    if linked is not None:
        user = session.get(User, linked.user_id)
        if user is None:
            raise IdentityConflict
        return user
    if session.scalar(select(User.id).where(User.email == identity.email)) is not None:
        raise IdentityConflict
    user = User(email=identity.email, password_hash=None)
    session.add(user)
    try:
        session.flush()
        session.add(
            ExternalIdentity(
                user_id=user.id, provider="google", subject=identity.subject
            )
        )
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise IdentityConflict from exc
    session.refresh(user)
    return user


def link_google_identity(
    session: Session, user: User, identity: GoogleIdentity
) -> None:
    existing = session.scalar(
        select(ExternalIdentity).where(
            ExternalIdentity.provider == "google",
            ExternalIdentity.subject == identity.subject,
        )
    )
    if existing is not None:
        if existing.user_id == user.id:
            return
        raise IdentityConflict
    session.add(
        ExternalIdentity(user_id=user.id, provider="google", subject=identity.subject)
    )
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise IdentityConflict from exc
