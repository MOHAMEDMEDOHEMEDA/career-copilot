from collections.abc import Callable
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Response, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from career_copilot_backend.core.database import get_db
from career_copilot_backend.schemas.auth import (
    AccessTokenResponse,
    Credentials,
    DisplayNameUpdate,
    GoogleTokenRequest,
    ProfileUpdate,
    RefreshRequest,
    UserResponse,
)
from career_copilot_backend.services.auth import (
    EmailAlreadyRegistered,
    authenticate_user,
    consume_refresh_token,
    get_access_user,
    issue_tokens,
    register_user,
    update_display_name,
)
from career_copilot_backend.services.google_auth import (
    GoogleAuthUnavailable,
    GoogleIdentity,
    IdentityConflict,
    InvalidGoogleToken,
    google_user,
    link_google_identity,
    verify_google_identity,
)

router = APIRouter()
Database = Annotated[Session, Depends(get_db)]
bearer = HTTPBearer(auto_error=False)


def google_verifier() -> Callable[[str], GoogleIdentity]:
    return verify_google_identity


def verified_google(
    token: str, verifier: Callable[[str], GoogleIdentity]
) -> GoogleIdentity:
    try:
        return verifier(token)
    except InvalidGoogleToken as exc:
        raise HTTPException(status_code=401, detail="Invalid Google sign-in") from exc
    except GoogleAuthUnavailable as exc:
        raise HTTPException(
            status_code=503, detail="Google sign-in unavailable"
        ) from exc


@router.post("/google", response_model=AccessTokenResponse)
def google_login(
    body: GoogleTokenRequest,
    session: Database,
    verifier: Annotated[Callable[[str], GoogleIdentity], Depends(google_verifier)],
) -> AccessTokenResponse:
    identity = verified_google(body.id_token, verifier)
    try:
        user = google_user(session, identity)
    except IdentityConflict as exc:
        raise HTTPException(
            status_code=409, detail="Sign in to your existing account to link Google"
        ) from exc
    try:
        token, refresh_token, lifetime = issue_tokens(session, user)
    except ValueError as exc:
        raise HTTPException(
            status_code=503, detail="Authentication unavailable"
        ) from exc
    return AccessTokenResponse(
        access_token=token, refresh_token=refresh_token, expires_in=lifetime
    )


@router.post("/google/link", status_code=204)
def google_link(
    body: GoogleTokenRequest,
    session: Database,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
    verifier: Annotated[Callable[[str], GoogleIdentity], Depends(google_verifier)],
) -> Response:
    user = get_access_user(session, credentials.credentials) if credentials else None
    if user is None:
        raise HTTPException(status_code=401, detail="Invalid access token")
    identity = verified_google(body.id_token, verifier)
    try:
        link_google_identity(session, user, identity)
    except IdentityConflict as exc:
        raise HTTPException(
            status_code=409, detail="Google account is already linked"
        ) from exc
    return Response(status_code=204)


@router.post(
    "/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED
)
def register(credentials: Credentials, session: Database) -> UserResponse:
    try:
        user = register_user(session, credentials.email, credentials.password)
    except EmailAlreadyRegistered as exc:
        raise HTTPException(status_code=409, detail="Email already registered") from exc
    return UserResponse.model_validate(user)


@router.post("/login", response_model=AccessTokenResponse)
def login(credentials: Credentials, session: Database) -> AccessTokenResponse:
    user = authenticate_user(session, credentials.email, credentials.password)
    if user is None:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    try:
        token, refresh_token, lifetime = issue_tokens(session, user)
    except ValueError as exc:
        raise HTTPException(
            status_code=503, detail="Authentication unavailable"
        ) from exc
    return AccessTokenResponse(
        access_token=token, refresh_token=refresh_token, expires_in=lifetime
    )


@router.post("/refresh", response_model=AccessTokenResponse)
def refresh(body: RefreshRequest, session: Database) -> AccessTokenResponse:
    user = consume_refresh_token(session, body.refresh_token)
    if user is None:
        raise HTTPException(status_code=401, detail="Invalid refresh token")
    try:
        token, refresh_token, lifetime = issue_tokens(session, user)
    except ValueError as exc:
        session.rollback()
        raise HTTPException(
            status_code=503, detail="Authentication unavailable"
        ) from exc
    return AccessTokenResponse(
        access_token=token, refresh_token=refresh_token, expires_in=lifetime
    )


@router.post("/logout", status_code=204)
def logout(body: RefreshRequest, session: Database) -> Response:
    consume_refresh_token(session, body.refresh_token)
    session.commit()
    return Response(status_code=204)


@router.get("/me", response_model=UserResponse)
def profile(
    session: Database,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> UserResponse:
    user = get_access_user(session, credentials.credentials) if credentials else None
    if user is None:
        raise HTTPException(
            status_code=401,
            detail="Invalid access token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return UserResponse.model_validate(user)


@router.patch("/me", response_model=UserResponse)
def update_profile(
    body: ProfileUpdate,
    session: Database,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> UserResponse:
    user = get_access_user(session, credentials.credentials) if credentials else None
    if user is None:
        raise HTTPException(status_code=401, detail="Invalid access token")
    if authenticate_user(session, user.email, body.password) is None:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    user.email = body.email.lower()
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(status_code=409, detail="Email already registered") from exc
    session.refresh(user)
    return UserResponse.model_validate(user)


@router.patch("/me/name", response_model=UserResponse)
def change_display_name(
    body: DisplayNameUpdate,
    session: Database,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> UserResponse:
    user = get_access_user(session, credentials.credentials) if credentials else None
    if user is None:
        raise HTTPException(status_code=401, detail="Invalid access token")
    return UserResponse.model_validate(update_display_name(session, user, body.display_name))
