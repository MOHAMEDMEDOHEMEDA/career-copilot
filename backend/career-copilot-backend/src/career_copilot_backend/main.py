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
    return JSONResponse(
        status_code=422,
        content={"error": {"code": "validation_error", "message": "Invalid request"}},
    )


@app.get("/health", tags=["health"])
async def health_check() -> dict[str, str]:
    return {"status": "healthy"}


@app.get("/", tags=["meta"])
async def root() -> dict[str, str]:
    return {"message": "Career Copilot API is running"}
