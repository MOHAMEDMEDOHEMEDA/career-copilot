# Career Copilot AI

Portfolio project: SwiftUI iOS app + FastAPI backend with RAG.
Full spec: `docs/spec.md`. Plan and milestones: `docs/implementation-plan.md`.
Never claim production usage, customers, or performance metrics.

## Stack
- iOS: Swift, SwiftUI, MVVM, async/await, URLSession, Keychain, SwiftData (cache only), XCTest. Min iOS 17 (configurable).
- Backend: Python 3.12, FastAPI, Pydantic v2, SQLAlchemy 2, Alembic, PostgreSQL + pgvector, pytest, uv, ruff, mypy.
- Auth: Argon2 password hashing, short-lived JWT access token, rotating refresh token.
- LLM: accessed only through the backend, behind a provider interface. Structured outputs. Mocked in tests.

## Layout
- `ios/CareerCopilot/`
- `backend/app/{api,schemas,services,llm,parsing,rag,models,repositories,core}`
- `backend/tests/`, `docs/`, `evals/`, `fixtures/` (synthetic data only)

## Rules
- Routes validate input, authorize, call services, return typed responses. No LLM calls in routes.
- All endpoints live under `/api/v1`. Use one consistent error shape. Paginate list endpoints.
- Every user-owned resource is ownership-checked. Each one gets a cross-user access test.
- Treat resume and PDF text as untrusted input (prompt injection). Never let it override system instructions.
- Validate every model output against a Pydantic schema. Reject or handle malformed output.
- Never log passwords, tokens, or resume text. Never commit secrets or real resumes. Only `.env.example` with placeholders.
- No automatic retries on expensive LLM calls. Use timeouts and cap input/output tokens.
- AI output must never invent skills, experience, or achievements.
- Do not present an AI-generated score as an objective measure of employability.
- Contracts first: update the OpenAPI/Pydantic schemas before writing client code.
- Prefer simple, maintainable code over extra abstraction.

## Commands
- Backend: `cd backend && uv run pytest` | `uv run ruff check .` | `uv run mypy app`
- Local stack: `docker compose up`
- iOS: `xcodebuild test -scheme CareerCopilot -destination 'platform=iOS Simulator,name=iPhone 15'`
  (adjust the simulator name to one installed locally)

## Working agreement
- Plan first. Wait for my approval before implementing.
- Work in small commits. Run tests and checks after each increment and fix failures before continuing.
- Say "implemented" only if the code exists. Say "verified" only if you ran it and show the output.
- End each milestone with a checklist: done / verified (with output) / not done.
- Update `docs/` when architecture or API contracts change.
- Ask a question only when a decision blocks progress. Otherwise state your assumption and proceed.
- Do not generate the whole app in one pass. Stay within the current milestone.
