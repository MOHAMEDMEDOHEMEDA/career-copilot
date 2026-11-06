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
For Google Sign-In, set `GOOGLE_SERVER_CLIENT_ID` (or `GOOGLE_CLIENT_ID`) to the Google OAuth web client ID. The iOS app sends a Google ID token to `/api/v1/auth/google`; existing accounts must first sign in and explicitly link using `/api/v1/auth/google/link`. No Google client secret is required by this token-exchange flow.
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

To smoke-test an already running backend, use `uv run python scripts/smoke_test.py --base-url http://localhost:8000`. The script creates a synthetic account, removes its uploaded resume, and leaves the account in place because account deletion is not yet implemented. The script does not yet cover analysis, matching, or chat.

The initial draft auth and resume API is documented in `../../docs/backend-contracts.md`.
Use `/docs` for the current implemented endpoints.

Analysis uses OpenRouter's free router. Set `OPENROUTER_API_KEY` in `.env`; never commit the key. After migrating, run `uv run python -m career_copilot_backend.services.analysis_jobs` alongside the API, or start Compose with `docker compose --profile analysis up --build`. Submit a resume ID to `POST /api/v1/resume-analysis`, then poll `GET /api/v1/jobs/{id}`. Use synthetic resumes until third-party data handling has been reviewed. The worker must be running to process queued jobs.

For requests that explicitly set `allow_provider_fallbacks: true`, the worker tries OpenRouter, local Ollama, then Gemini once each when the previous provider fails. Add `GEMINI_API_KEY` to `.env` to enable Gemini and keep the key out of source control. Google offers a free tier with limits; a billed Google project can incur charges. Ollama defaults to the local `llama3.2:latest` model and must be running on port 11434. Set `OLLAMA_ENABLED=false` to disable it or `OLLAMA_MODEL` to another installed local model. Docker connects to the host via `host.docker.internal:11434`; a worker run directly on the host defaults to `127.0.0.1:11434`. Gemini's free tier may use content to improve Google's products, so use synthetic data until the privacy review is complete. Existing clients that omit the flag remain limited to OpenRouter.

The RAG corpus is project-authored example guidance, not a comprehensive source of expert advice. Install Ollama's `nomic-embed-text:latest`, apply migrations, and run `uv run python -m career_copilot_backend.knowledge.index` to create the local pgvector index. Reindex after changing the corpus. `uv run python scripts/eval_retrieval.py` runs a small synthetic smoke evaluation. Retrieval and answer quality must be evaluated further before release.
