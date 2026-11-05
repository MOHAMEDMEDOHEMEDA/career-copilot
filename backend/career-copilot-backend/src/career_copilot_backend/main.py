import logging
from uuid import uuid4

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException

from career_copilot_backend.api.v1.router import api_router
from career_copilot_backend.core.config import settings

app = FastAPI(
    title="Career Copilot API",
    description="AI-powered career assistant",
    version="0.1.0",
)

app.include_router(api_router, prefix=settings.api_v1_prefix)

logger = logging.getLogger("career_copilot.requests")


@app.middleware("http")
async def request_context(request: Request, call_next):
    request_id = str(uuid4())
    request.state.request_id = request_id
    response = await call_next(request)
    response.headers["X-Request-ID"] = request_id
    logger.info(
        "request_id=%s method=%s status=%s",
        request_id,
        request.method,
        response.status_code,
    )
    return response


@app.exception_handler(HTTPException)
async def http_error_handler(request: Request, exc: HTTPException) -> JSONResponse:
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": {"code": "http_error", "message": str(exc.detail)}},
        headers=exc.headers,
    )


@app.exception_handler(RequestValidationError)
async def validation_error_handler(
    request: Request, exc: RequestValidationError
) -> JSONResponse:
    messages = []
    for error in exc.errors():
        location = error.get("loc", ())
        field = location[-1] if location else None
        error_type = error.get("type")
        if field == "email":
            message = "Enter a valid email address."
        elif field == "password":
            message = "Password must be between 8 and 128 characters."
        elif field == "file":
            message = "Choose a PDF file to upload."
        elif field == "resume_id":
            message = "The resume ID is invalid."
        else:
            message = "Check the submitted information and try again."
        if error_type == "missing" and field == "password":
            message = "Enter your password."
        if message not in messages:
            messages.append(message)
    return JSONResponse(
        status_code=422,
        content={"error": {"code": "validation_error", "message": " ".join(messages)}},
    )


@app.get("/health", tags=["health"])
async def health_check() -> dict[str, str]:
    return {"status": "healthy"}


@app.get("/", tags=["meta"])
async def root() -> dict[str, str]:
    return {"message": "Career Copilot API is running"}
