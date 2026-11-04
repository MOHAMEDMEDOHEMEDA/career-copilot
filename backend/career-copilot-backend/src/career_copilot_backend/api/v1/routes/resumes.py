from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, File, HTTPException, Query, Response, UploadFile
from fastapi.security import HTTPAuthorizationCredentials
from sqlalchemy.orm import Session

from career_copilot_backend.api.v1.routes.auth import bearer
from career_copilot_backend.core.database import get_db
from career_copilot_backend.models import User
from career_copilot_backend.parsing.pdf import (
    MAX_PDF_BYTES,
    InvalidPDF,
    PDFRequiresOCR,
    PDFTooLarge,
    extract_pdf_text,
)
from career_copilot_backend.schemas.resume import (
    ResumePage,
    ResumeResponse,
    ResumeUpdate,
)
from career_copilot_backend.services.auth import get_access_user
from career_copilot_backend.services.resumes import (
    find_resume,
    list_resumes,
    save_resume,
)

router = APIRouter()
Database = Annotated[Session, Depends(get_db)]


def current_user(
    session: Database,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> User:
    user = get_access_user(session, credentials.credentials) if credentials else None
    if user is None:
        raise HTTPException(
            status_code=401,
            detail="Invalid access token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user


CurrentUser = Annotated[User, Depends(current_user)]


@router.post("", response_model=ResumeResponse, status_code=201)
async def upload_resume(
    session: Database, user: CurrentUser, file: Annotated[UploadFile, File()]
) -> ResumeResponse:
    content = await file.read(MAX_PDF_BYTES + 1)
    try:
        text = extract_pdf_text(content, file.content_type)
    except PDFTooLarge as exc:
        raise HTTPException(status_code=413, detail=str(exc)) from exc
    except (InvalidPDF, PDFRequiresOCR) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    filename = (file.filename or "resume.pdf").replace("\\", "/").split("/")[-1][
        :255
    ] or "resume.pdf"
    return ResumeResponse.model_validate(save_resume(session, user.id, filename, text))


@router.get("", response_model=ResumePage)
def get_resumes(
    session: Database,
    user: CurrentUser,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> ResumePage:
    return ResumePage(
        items=[
            ResumeResponse.model_validate(resume)
            for resume in list_resumes(session, user.id, limit, offset)
        ],
        limit=limit,
        offset=offset,
    )


def owned_resume(session: Session, user: User, resume_id: UUID):
    resume = find_resume(session, user.id, resume_id)
    if resume is None:
        raise HTTPException(status_code=404, detail="Resume not found")
    return resume


@router.get("/{resume_id}", response_model=ResumeResponse)
def get_resume(resume_id: UUID, session: Database, user: CurrentUser) -> ResumeResponse:
    return ResumeResponse.model_validate(owned_resume(session, user, resume_id))


@router.patch("/{resume_id}", response_model=ResumeResponse)
def update_resume(
    resume_id: UUID, body: ResumeUpdate, session: Database, user: CurrentUser
) -> ResumeResponse:
    resume = owned_resume(session, user, resume_id)
    resume.text = body.text
    session.commit()
    session.refresh(resume)
    return ResumeResponse.model_validate(resume)


@router.delete("/{resume_id}", status_code=204)
def delete_resume(resume_id: UUID, session: Database, user: CurrentUser) -> Response:
    session.delete(owned_resume(session, user, resume_id))
    session.commit()
    return Response(status_code=204)
