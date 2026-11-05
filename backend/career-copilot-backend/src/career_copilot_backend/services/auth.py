import hashlib
import secrets
from datetime import UTC, datetime, timedelta
from uuid import UUID

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from career_copilot_backend.core.config import settings
from career_copilot_backend.models import RefreshToken, User

password_hasher = PasswordHasher()


class EmailAlreadyRegistered(Exception):
    pass


def register_user(session: Session, email: str, password: str) -> User:
    user = User(email=email.lower(), password_hash=password_hasher.hash(password))
    session.add(user)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise EmailAlreadyRegistered from exc
    session.refresh(user)
    return user


def authenticate_user(session: Session, email: str, password: str) -> User | None:
    user = session.scalar(select(User).where(User.email == email.lower()))
    if user is None or user.password_hash is None:
        return None
    try:
        password_hasher.verify(user.password_hash, password)
    except (VerifyMismatchError, InvalidHashError):
        return None
    return user


def create_access_token(user: User) -> tuple[str, int]:
    if len(settings.jwt_secret) < 32:
        raise ValueError("JWT_SECRET must be at least 32 characters")
    lifetime = settings.access_token_minutes * 60
    now = datetime.now(UTC)
    token = jwt.encode(
        {"sub": str(user.id), "iat": now, "exp": now + timedelta(seconds=lifetime)},
        settings.jwt_secret,
        algorithm="HS256",
    )
    return token, lifetime


def issue_tokens(session: Session, user: User) -> tuple[str, str, int]:
    access_token, lifetime = create_access_token(user)
    refresh_token = secrets.token_urlsafe(32)
    session.add(
        RefreshToken(
            user_id=user.id,
            token_hash=hashlib.sha256(refresh_token.encode()).hexdigest(),
            expires_at=datetime.now(UTC) + timedelta(days=settings.refresh_token_days),
        )
    )
    session.commit()
    return access_token, refresh_token, lifetime


def consume_refresh_token(session: Session, token: str) -> User | None:
    now = datetime.now(UTC)
    token_hash = hashlib.sha256(token.encode()).hexdigest()
    user_id = session.execute(
        update(RefreshToken)
        .where(
            RefreshToken.token_hash == token_hash,
            RefreshToken.revoked_at.is_(None),
            RefreshToken.expires_at > now,
        )
        .values(revoked_at=now)
        .returning(RefreshToken.user_id)
    ).scalar_one_or_none()
    if user_id is None:
        session.rollback()
        return None
    return session.get(User, user_id)


def get_access_user(session: Session, token: str) -> User | None:
    if len(settings.jwt_secret) < 32:
        return None
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret,
            algorithms=["HS256"],
            options={"require": ["sub", "iat", "exp"]},
        )
        user_id = UUID(payload["sub"])
    except (jwt.InvalidTokenError, ValueError, TypeError, KeyError):
        return None
    return session.get(User, user_id)
