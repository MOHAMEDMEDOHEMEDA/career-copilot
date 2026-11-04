# Career Copilot Backend

FastAPI backend for the Career Copilot AI portfolio project.

## Local setup

Requirements: Python 3.12 and `uv`.

```bash
uv sync --dev
cp .env.example .env
uv run uvicorn career_copilot_backend.main:app --reload
```

The API is available at `http://localhost:8000`. Interactive documentation is
available at `/docs`, and health checks are at `/health` and `/api/v1/health`.

## Database

Start the API and local PostgreSQL database with pgvector:

```bash
docker compose up --build
```

## Checks

```bash
uv run pytest
uv run ruff check .
uv run mypy src
```

The proposed auth and resume API is documented in `../../docs/backend-contracts.md`.
Those endpoints are not implemented yet.
