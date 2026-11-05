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

To smoke-test an already running backend, use `uv run python scripts/smoke_test.py --base-url http://localhost:8000`. The script creates a synthetic account, removes its uploaded resume, and leaves the account in place because account deletion is not yet implemented. Analysis, matching, and chat are not implemented, so this is not yet the full cross-phase smoke test.

The initial draft auth and resume API is documented in `../../docs/backend-contracts.md`.
Use `/docs` for the current implemented endpoints.

Analysis uses OpenRouter's free router. Set `OPENROUTER_API_KEY` in `.env`; never commit the key. After migrating, run `uv run python -m career_copilot_backend.services.analysis_jobs` alongside the API, or start Compose with `docker compose --profile analysis up --build`. Submit a resume ID to `POST /api/v1/resume-analysis`, then poll `GET /api/v1/jobs/{id}`. Use synthetic resumes until third-party data handling has been reviewed. The worker must be running to process queued jobs.
