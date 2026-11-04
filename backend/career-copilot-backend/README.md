# Career Copilot Backend

FastAPI backend for the Career Copilot AI portfolio project.

## Local setup

Requirements: Python 3.12 and `uv`.

```bash
uv sync --dev
cp .env.example .env
uv run uvicorn career_copilot_backend.main:app --reload
```

Set `JWT_SECRET` in `.env` to a unique random value of at least 32 characters before using login. Never use the example value outside local development.
Compose also reads `JWT_SECRET` from this `.env` file. Run migrations before using authentication.

The API is available at `http://localhost:8000`. Interactive documentation is
available at `/docs`, and health checks are at `/health` and `/api/v1/health`.

## Database

Start the API and local PostgreSQL database with pgvector:

```bash
docker compose up --build
```

Apply database migrations from the backend directory after starting the database:

```bash
uv run alembic upgrade head
```

## Checks

```bash
uv run pytest
uv run ruff check .
uv run mypy src
```

The proposed auth and resume API is documented in `../../docs/backend-contracts.md`.
Those endpoints are not implemented yet.
