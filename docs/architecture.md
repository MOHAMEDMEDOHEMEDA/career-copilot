# Architecture decisions

## Database

PostgreSQL is the system of record. SQLAlchemy manages database access, and Alembic tracks schema changes. The first migration creates users with unique email addresses and Argon2 password hashes. Database connections are configured through `DATABASE_URL`.

## Authentication

Registration stores Argon2 password hashes. Login issues short-lived HS256 access tokens signed with `JWT_SECRET`, which must be at least 32 characters, and random refresh tokens. Refresh tokens are stored as SHA-256 hashes, expire after 30 days by default, and are rotated atomically on use. Logout revokes the submitted refresh token; issued access tokens remain valid until expiry. `GET /api/v1/auth/me` returns the authenticated profile; `PATCH /api/v1/auth/me` updates email after password confirmation. Request logs include generated request IDs, methods, and status codes, without request bodies or credentials. Automatic cleanup of expired refresh token records is not yet implemented.

## Resume storage

Authenticated users can upload PDFs of up to 10 MiB, extract their text, and list, read, edit, or delete their own resumes. The original PDF is not stored. Textless documents receive an OCR-required error; OCR is not implemented. Resume text is untrusted input and must not be logged or treated as instructions. Structured field extraction and background analysis are not implemented yet.
