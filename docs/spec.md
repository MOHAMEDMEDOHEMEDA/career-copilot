# Career Copilot AI: Spec (v1)

## 1. Overview
An AI career assistant for iOS. Users upload a resume, get structured analysis, match it against job descriptions, and ask career questions answered from a curated document set using RAG. Mock interviews follow in v1.1.

This is a portfolio project. Do not claim production usage, customers, or metrics unless verified. Use synthetic resumes and rights-cleared documents only.

## 2. Stack and decisions
**iOS:** Swift, SwiftUI, MVVM, async/await, URLSession, Keychain for tokens, SwiftData for caching only, XCTest. Minimum iOS 17, configurable.

**Backend:** Python 3.12, FastAPI, Pydantic v2, SQLAlchemy 2, Alembic, PostgreSQL with pgvector, pytest, uv, ruff, mypy.

**Auth:** Argon2 hashing, short-lived JWT access token, rotating refresh token, logout revokes refresh tokens.

**LLM:** one provider behind an interface so it can be swapped. Structured outputs. Hard caps on input and output tokens. Keys stay on the backend.

**Long operations:** analysis runs as a background job with a status endpoint. The iOS app polls (or streams later).

Document each decision and its trade-off in `docs/architecture.md`.

## 3. Features

### A. Authentication and users
Register, login, refresh, logout, profile management, per-user data isolation. Clear loading, validation, and error states.

### B. Resume management
Upload PDFs (type and size validated on the backend). Extract text. Store text and structured fields. Users can review, edit, and delete resumes, and deletion removes all associated data. Scanned PDFs get a clear message that OCR is required.

### C. AI resume analysis
Return a validated Pydantic schema with: summary, technical and soft skills, experience, education, strengths, improvement suggestions, missing or unclear information, and bullet rewrites that do not invent achievements.
- Treat resume text as untrusted input.
- No arbitrary employability score. If one is added later, define its rubric and limits.

### D. Job description matching
Compare a pasted job description to a selected resume. Return: required skills found, required skills not demonstrated, evidence from the resume, experience alignment, recommendations, and interview topics.
- Distinguish "absent from the resume" from "the user lacks this skill".
- Never fabricate experience.

### E. Mock interview (v1.1)
Generate questions from the job description and resume. Accept text answers. Grade with an explicit rubric (correctness, completeness, relevance, clarity). Explain strengths and gaps, give a stronger example answer, and track sessions. Do not grade by similarity to a model answer.

### F. RAG career assistant
Separate, testable components: ingestion, chunking, embeddings, retrieval, answer generation, evaluation.
- Small curated collection, rights-cleared only.
- Store embeddings and metadata in pgvector.
- Answers cite source titles and excerpts or page references.
- When sources are insufficient, say so instead of guessing.

## 4. iOS screens
1. Onboarding and authentication
2. Home dashboard
3. Resume list and upload
4. Resume analysis results
5. Job description input and match results
6. RAG chat with citations
7. Profile and settings
8. Mock interview and feedback (v1.1)

Use reusable components, consistent typography and spacing, accessibility labels, and support for different screen sizes. Provide loading, empty, offline, retry, and error states. Split features into small views; no giant files.

## 5. Backend architecture
Layers: API routes, schemas, services, LLM provider and prompts, resume parsing, embedding and retrieval, models and repositories, auth, configuration, tests.

Routes validate, authorize, call services, and return typed responses. Provider calls never live in route handlers.

Endpoints under `/api/v1`: `auth`, `users`, `resumes`, `resume-analysis`, `job-matches`, `interviews`, `knowledge`, `chat`. Finalize contracts (OpenAPI) before building the iOS client. Use one consistent error format and correct HTTP status codes.

## 6. Production requirements

**Security:** hashed passwords, tokens in Keychain, ownership checks on every resource, upload limits, rate limits, scoped CORS, no sensitive data in logs, data deletion, `.env.example` with placeholders only.

**Prompt injection:** resume and document text is untrusted. Include at least one test with a malicious PDF and strict schema validation of outputs.

**Privacy:** document what is stored and for how long. Account deletion is tested end to end.

**Reliability:** timeouts, controlled retries, provider-failure handling, validated model output, no automatic retry of expensive requests, observable and recoverable long jobs, pagination, request IDs, structured privacy-safe logs.

**Cost:** track usage and estimated cost, limit input and output sizes, avoid repeat calls, cache only when safe, enforce per-user limits.

**Testing:**
- iOS: ViewModel, networking, and business-logic unit tests.
- Backend: unit and API integration tests, auth and authorization tests.
- Invalid PDFs, malformed model output, timeouts, provider errors.
- RAG retrieval tests with known queries and expected documents.
- Cross-user access tests for resumes and conversations.
- Eval datasets with expected criteria and documented limitations.
- Mock model responses in most tests.

**Fixtures:** keep synthetic resumes and job descriptions in `fixtures/` for tests, evals, and screenshots.

## 7. Deployment and developer experience
Clear repo structure, backend Dockerfile, Docker Compose for local development, Alembic migrations, `/health` endpoint, CI (ruff, mypy, pytest), instructions to run iOS against local or deployed backends, a deployment guide, architecture diagram, API docs, README (setup, features, limitations, screenshots), and a short demo script.

## 8. Milestones
Build order: backend first, then AI, then the iOS app. Each milestone ends with a gate. Do not start the next until the gate passes.

### Phase A: Backend foundation
- **M0 Foundation:** repo, docs, OpenAPI contracts for auth and resumes, `.env.example`, docker-compose, `/health`, CI. Gate: compose runs, health returns 200, CI green.
- **M1 Auth and data layer:** register, login, refresh, logout, profile, migrations, error format, request IDs, safe logging. Gate: auth tests pass, including expired and reused tokens.
- **M2 Resume pipeline:** upload, PDF validation and extraction, scanned-PDF message, resume CRUD and deletion, background job framework with a status endpoint, usage-tracking tables, rate limits, smoke-test script. Gate: tests for corrupt, oversized, and scanned PDFs and cross-user access; everything works through `/docs`. Deploy the backend to a hosted URL and tag the OpenAPI spec.
- **M2.5 iOS spike (half day):** minimal app that logs in, stores the token in Keychain, and calls one endpoint on the hosted backend. Gate: token refresh and base URL configuration work. Do this before starting Phase B.

### Phase B: AI layer
- **M3 Resume analysis:** LLM provider interface, structured outputs, analysis schema, prompt-injection tests, malformed-output and timeout tests, mocked responses. Gate: tests pass, plus one manual run with the real provider.
- **M4 Job matching:** schema, evidence, absent-vs-not-possessed wording. Gate: mocked tests pass, no fabricated experience.
- **M5 RAG and evals:** curated documents, chunking, embeddings, retrieval, cited answers, "not enough information" behavior, eval dataset and script. Gate: retrieval tests pass, results and limitations documented. Tag the OpenAPI spec.

### Phase C: iOS app
- **M6 iOS foundation:** networking layer with models generated from the OpenAPI spec, Keychain, auth screens, resume upload and list. Gate: flow works in the simulator, unit tests pass.
- **M7 iOS features:** analysis results, job matching, RAG chat with sources, profile and settings, all loading, empty, offline, retry, and error states.
- **M8 iOS tests and device run:** ViewModel and networking tests, real-device run against the hosted backend. Gate: full flow works on a device.

### Phase D: Hardening and release
- **M9 Hardening and release:** usage caps, CORS, log scrubbing, deletion tested end to end, pagination, security review, deployment guide, README with screenshots, architecture diagram, demo script, TestFlight or demo video. Gate: no open high-severity findings; a newcomer can follow the README and run the demo.

### Optional
- **M10 Mock interviews (v1.1).**
- **M11 Market study and monetization decision:** complete `docs/market-study.md`. Gate: go / pivot / stay-portfolio decision recorded against the decision rule set beforehand. Only if "go": add in-app purchases, privacy policy, and usage-based cost controls before charging anyone.

### Cross-phase rules
- Freeze and tag the OpenAPI spec at the end of each backend milestone; the iOS client is generated from it.
- Keep a smoke-test script that runs the full flow (register, upload, analyze, match, chat) and run it after every backend change.
- Review backend diffs closely: auth, SQL, and upload handling.

If time runs short, cut in this order: interviews, SwiftData caching, extra eval cases. Never cut security, isolation tests, or the README.

## 9. Working rules
Inspect the repo first. Plan before coding. Small, testable increments. Run tests after each. Fix failures before moving on. Do not claim a feature is implemented, tested, or deployed unless verified. Prefer simple, maintainable solutions. Ask questions only when blocked.

## 10. Definition of done
- Core iOS workflow works end to end.
- Backend runs and deploys using documented steps.
- No model keys in the client or repo.
- User data is isolated and tested.
- Main workflows have automated tests.
- RAG answers include verifiable sources.
- AI quality is evaluated with a documented dataset and method.
- Errors and provider failures are handled gracefully.
- CI and setup docs exist.
- A recruiter can understand the architecture and run the demo.
