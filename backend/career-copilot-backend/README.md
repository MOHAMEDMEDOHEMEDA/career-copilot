# Career Copilot Backend

FastAPI backend for the Career Copilot AI portfolio project. It provides authentication, resume storage and analysis, job matching, career chat, and standard and adaptive mock interviews. AI calls run in a separate worker through a configurable provider interface.

## Requirements

- Python 3.12 or later and `uv` for local development and migrations.
- Docker and Docker Compose for PostgreSQL with pgvector and, optionally, the API and worker.
- At least one configured AI provider for AI features. Ollama is also required for knowledge indexing and retrieval.

Run the following commands from this directory. Create local configuration and dependencies:

```bash
uv sync --dev
cp .env.example .env
```

Edit `.env` and set `JWT_SECRET` to a unique random value of at least 32 characters. Set the AI provider keys and Google client ID if you intend to use those features. The example values are placeholders; never commit `.env`, API keys, or real resumes.

## Start the local stack

Start PostgreSQL, the API, and the worker, then apply migrations from the host:

```bash
docker compose --profile analysis up -d --build
uv run alembic upgrade head
```

Compose reads `.env` from this directory. The API is at `http://localhost:8000`, its interactive API documentation is at `/docs`, and health endpoints are `/health` and `/api/v1/health`. The worker must be running to process analysis, matching, chat, and interview jobs. Queued jobs are stored in the database.

Alternatively, start just the database with `docker compose up -d db`, then run these in separate terminals after migrating:

```bash
uv run uvicorn career_copilot_backend.main:app --reload
```

```bash
uv run python -m career_copilot_backend.services.analysis_jobs
```

The host-run API and worker use the `DATABASE_URL` in `.env`; the example targets `localhost:5432`. Docker services use `db:5432` and reach Ollama on the host via `host.docker.internal:11434`.

## Authentication

Password authentication uses Argon2 and rotating refresh tokens. Google Sign-In requires `GOOGLE_SERVER_CLIENT_ID` in `.env`, set to the Google OAuth web client ID used by the iOS app. The backend verifies the Google ID token; an existing password account must explicitly link its Google identity. See the [iOS README](../../ios/CareerCopilot/README.md) for client setup. Google sign-in was exercised in the simulator; linking an existing account still needs real-account verification.

## AI providers and privacy

Set `OPENROUTER_API_KEY` to use the OpenRouter free router. When a request explicitly permits fallbacks, the configured chain tries OpenRouter, local Ollama, and then Gemini, with at most one attempt per configured provider. Set `GEMINI_API_KEY` to enable Gemini; omit it to skip Gemini. Ollama defaults to `llama3.2:latest` on port 11434; set `OLLAMA_MODEL` to an installed local model or `OLLAMA_ENABLED=false` to disable this fallback. Free-model availability and quotas can change, and a billed provider account may incur costs.

Inputs and retrieved text are treated as untrusted data, and model outputs are validated. These protections do not guarantee factual accuracy. Resume text, job descriptions, questions, and answers can be sent to cloud providers after the app's disclosure. Google’s free tier may use content to improve products. Use synthetic data until provider privacy and retention are reviewed.

## Knowledge base and chat

The project-authored corpus is in `src/career_copilot_backend/knowledge/corpus.json`. Install and start Ollama, pull the `nomic-embed-text:latest` embedding model, apply migrations, and index the corpus from the host:

```bash
ollama pull nomic-embed-text:latest
uv run python -m career_copilot_backend.knowledge.index
```

Reindex after changing the corpus. Indexing uses the local Ollama embedder and stores vectors in pgvector. Chat retrieves source excerpts and can return insufficient information if nothing relevant is found. The corpus and retrieval quality need further review; a citation does not prove every generated statement is supported.

## Adaptive interviews

The separate `/api/v1/interviews/adaptive` API supports session setup, optional owned resumes, question and evaluation jobs, explicit retry, completion, reports, and topic progress. Existing standard interview endpoints remain available. Difficulty and follow-ups use backend policy based on model-generated coaching feedback; scores are approximate, not verified measures of proficiency. An explicit “I don't know” response can receive an unscored AI-generated example answer.

Optional technical retrieval is restricted to sources marked `technical_reference` and listed in the comma-separated `REVIEWED_TECHNICAL_SOURCE_IDS` setting. The list is empty by default. Review source accuracy and rights before enabling sources, and reindex after corpus changes. `ADAPTIVE_INTERVIEW_LIMIT_PER_HOUR` and `ADAPTIVE_MAX_FOLLOWUPS` configure interview request limits and follow-up depth.

## Checks and evaluation

```bash
uv run pytest
uv run ruff check .
uv run mypy src
uv run python scripts/smoke_test.py --base-url http://localhost:8000
uv run python scripts/eval_retrieval.py
uv run python scripts/eval_adaptive.py
```

The smoke test creates a synthetic account and removes its uploaded resume, but leaves the account because account deletion is not implemented; it does not yet cover the full AI flow. Retrieval and adaptive scripts are small synthetic smoke evaluations, not measurements of real-world model quality. The retrieval evaluation requires the corpus to be indexed and Ollama to be available.

## Remaining work

Account deletion, broader AI and retrieval evaluation, reviewed technical sources, a full end-to-end smoke test, hosted deployment, privacy and retention review, and production hardening remain. The [architecture](../../docs/architecture.md) and [backend contracts](../../docs/backend-contracts.md) contain further details; `/docs` reflects the running API.
