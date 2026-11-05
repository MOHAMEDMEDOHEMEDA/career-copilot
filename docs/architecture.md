# Architecture decisions

## Database

PostgreSQL is the system of record. SQLAlchemy manages database access, and Alembic tracks schema changes. The first migration creates users with unique email addresses and Argon2 password hashes. Database connections are configured through `DATABASE_URL`.

## Authentication

Registration stores Argon2 password hashes. Login issues short-lived HS256 access tokens signed with `JWT_SECRET`, which must be at least 32 characters, and random refresh tokens. Refresh tokens are stored as SHA-256 hashes, expire after 30 days by default, and are rotated atomically on use. Logout revokes the submitted refresh token; issued access tokens remain valid until expiry. `GET /api/v1/auth/me` returns the authenticated profile; `PATCH /api/v1/auth/me` updates email after password confirmation. Request logs include generated request IDs, methods, and status codes, without request bodies or credentials. Automatic cleanup of expired refresh token records is not yet implemented.

## Resume storage

Authenticated users can upload PDFs of up to 10 MiB, extract their text, and list, read, edit, or delete their own resumes. The original PDF is not stored. Textless documents receive an OCR-required error; OCR is not implemented. Resume text is untrusted input and must not be logged or treated as instructions. Structured field extraction and background analysis are not implemented yet.

Upload attempts are recorded without document content in `usage_events` and limited to 20 per user per rolling hour by default. The limit is configurable using `UPLOAD_LIMIT_PER_HOUR`. PostgreSQL row locking serializes concurrent attempts for each user; this limit does not protect unauthenticated endpoints or replace an upstream request-size limit.

## Jobs

The database stores job records and `GET /api/v1/jobs/{job_id}` returns status and completed results only to the owning user. The worker claims queued jobs with database locks and a lease; expired running jobs are marked failed instead of automatically retrying potentially expensive work. A stale worker cannot update a job after its lease is cleared. Start the worker separately with `python -m career_copilot_backend.services.analysis_jobs` or the Compose `analysis` profile. Queued jobs persist while the worker is stopped.

## Resume analysis foundation

The analysis service sends the system instruction and untrusted resume text as separate provider inputs, requests a structured schema, sets an output-token limit and timeout, and validates the returned JSON. It also caps input and output characters. The OpenRouter adapter uses the `openrouter/free` router, requests structured-output support, disallows provider fallback and requests providers that deny data collection. Availability depends on OpenRouter's free-model and privacy settings; the model can vary between requests. Resume text is sent to a third party, so use synthetic data until privacy and retention policies are reviewed. This separation and schema validation do not guarantee factual output or immunity to prompt injection. Input tokens are not counted yet. Analysis requests are limited to five per user per hour by default, and completed results persist on the job until its resume is deleted.
