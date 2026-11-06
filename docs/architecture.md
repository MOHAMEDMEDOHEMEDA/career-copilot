# Architecture decisions

## Database

PostgreSQL is the system of record. SQLAlchemy manages database access, and Alembic tracks schema changes. The first migration creates users with unique email addresses and Argon2 password hashes. Database connections are configured through `DATABASE_URL`.

## Authentication

Registration stores Argon2 password hashes. Login issues short-lived HS256 access tokens signed with `JWT_SECRET`, which must be at least 32 characters, and random refresh tokens. Refresh tokens are stored as SHA-256 hashes, expire after 30 days by default, and are rotated atomically on use. Logout revokes the submitted refresh token; issued access tokens remain valid until expiry. `GET /api/v1/auth/me` returns the authenticated profile; `PATCH /api/v1/auth/me` updates email after password confirmation. Request logs include generated request IDs, methods, and status codes, without request bodies or credentials. Automatic cleanup of expired refresh token records is not yet implemented.

Validation errors retain the standard error envelope and use safe, field-specific messages where available. The response never includes submitted values or raw validation error details.

Google Sign-In exchanges a verified Google ID token for the same application token pair as password login. The backend validates the token using Google's verification library and the configured server client ID, requires a verified email, and identifies accounts by Google's stable subject. Existing password accounts are never linked automatically by email: an authenticated user must explicitly link their Google identity. Google-only users have no password; password-only profile changes are unavailable to them until an appropriate reauthentication flow is implemented. The provider integration is not verified against real Google credentials yet.

## Resume storage

Authenticated users can upload PDFs of up to 10 MiB, extract their text, and list, read, edit, or delete their own resumes. The original PDF is not stored. Textless documents receive an OCR-required error; OCR is not implemented. Resume text is untrusted input and must not be logged or treated as instructions.

Upload attempts are recorded without document content in `usage_events` and limited to 20 per user per rolling hour by default. The limit is configurable using `UPLOAD_LIMIT_PER_HOUR`. PostgreSQL row locking serializes concurrent attempts for each user; this limit does not protect unauthenticated endpoints or replace an upstream request-size limit.

## Jobs

The database stores job records and `GET /api/v1/jobs/{job_id}` returns status and completed results only to the owning user. The worker claims queued jobs with database locks and a lease; expired running jobs are marked failed instead of automatically retrying potentially expensive work. A stale worker cannot update a job after its lease is cleared. Start the worker separately with `python -m career_copilot_backend.services.analysis_jobs` or the Compose `analysis` profile. Queued jobs persist while the worker is stopped.

`GET /api/v1/jobs?resume_id=...` returns paginated analysis history for an owned resume. Jobs store a small allowlisted error code instead of provider messages or personal text; existing failed jobs may have no code. Results can reflect an older version of an edited resume and are deleted when its resume is deleted.

Job failures distinguish safe categories such as rate limits, provider availability, malformed output, and unsupported resume evidence. They do not persist raw provider responses, input text in error messages, or exception details. Previously recorded generic failures cannot be diagnosed retrospectively from their error code.

## Resume analysis foundation

The analysis service sends the system instruction and untrusted resume text as separate provider inputs, requests a structured schema, sets an output-token limit and timeout, and validates the returned JSON. It also caps input and output characters. The OpenRouter adapter uses the `openrouter/free` router, requests structured-output support, disallows provider fallback and requests providers that deny data collection. Availability depends on OpenRouter's free-model and privacy settings; the model can vary between requests. Free models are subject to provider and account rate limits. Resume text is sent to a third party, so use synthetic data until privacy and retention policies are reviewed. This separation and schema validation do not guarantee factual output or immunity to prompt injection. Input tokens are not counted yet. Analysis requests are limited to five per user per hour by default, and completed results persist on the job until its resume is deleted.

At the user's request, provider failures trigger at most one attempt each in order: OpenRouter, local Ollama (`llama3.2:latest` by default), then Google Gemini (`gemini-2.5-flash-lite`) when its API key is configured. Fallbacks are used only when the request contains `allow_provider_fallbacks: true`, after the app discloses both cloud providers; older clients default to OpenRouter only. Missing credentials skip their cloud provider; cancellation stops the chain. Each attempt has a timeout and output cap. Invalid JSON or schema responses can trigger the next provider; unsupported resume evidence is rejected without another attempt. Google states its free tier may use content to improve products. Use synthetic data until privacy is reviewed. Gemini's free quota depends on account configuration: a billed Google project can incur charges. Docker uses `host.docker.internal:11434` to reach Ollama on the host.

## Job matching contract

`POST /api/v1/job-matches` accepts an owned `resume_id` and `job_description` (at most 20,000 characters), returns a 202 job, and uses `GET /api/v1/jobs/{id}` for status and results. The result contains found skills with exact resume excerpts, requirements not demonstrated in the resume, experience alignment, recommendations, and interview topics. The worker validates quoted skill evidence against the resume, but cannot guarantee that every generated statement is factual; users must review the result. Both inputs are untrusted and are processed only after user confirmation. The job description is temporarily stored while queued/running and removed when processing finishes or its lease expires. Results remain until the resume is deleted. Matching requests use a separate per-user hourly limit equal to `ANALYSIS_LIMIT_PER_HOUR`; jobs are not requeued automatically, but the worker may try the configured fallback providers as described above.

## Chat foundation

Conversations belong to one user and store a title and ordered messages. Access requires authentication and an ownership check. Message sequence numbers are assigned while locking the conversation row; lists are paginated. Deleting a conversation deletes its messages, and database foreign keys cascade when a user is deleted. Message content and titles are stored until deletion and must not be logged. Only user-authored messages can be created by the API at this stage; retrieval, citations, and AI replies are not implemented.
