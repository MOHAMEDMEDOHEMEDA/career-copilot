# Backend API contracts (draft)

These contracts describe planned endpoints under `/api/v1`; they are not yet implemented. Final OpenAPI schemas must be agreed and implemented before the iOS client uses them.

All errors use `{"error":{"code":"...","message":"..."}}`. Authentication uses a bearer access token. List responses include `items`, `limit`, and `offset`.

## Authentication

The current Google exchange adds `POST /api/v1/auth/google` with an `id_token` request and the existing token-pair response. `POST /api/v1/auth/google/link` accepts the same request and requires a bearer access token; it returns `204` on success and `409` on an identity conflict. Both return `401` for an invalid Google token and `503` if verification is unavailable. Email matches do not automatically link accounts. The original draft table below predates these additions; use the running `/openapi.json` for the current implemented schema.

| Method and path | Request | Successful response |
| --- | --- | --- |
| `POST /auth/register` | email and password | `201` user profile |
| `POST /auth/login` | email and password | `200` access token, refresh token, token type and expiry |
| `POST /auth/refresh` | refresh token | `200` rotated token pair |
| `POST /auth/logout` | refresh token | `204`; refresh token revoked |

## Resumes

All resume operations require authentication and enforce ownership.

| Method and path | Request | Successful response |
| --- | --- | --- |
| `POST /resumes` | multipart PDF upload | `201` resume |
| `GET /resumes` | `limit`, `offset` | `200` paginated resumes |
| `GET /resumes/{resume_id}` | resume ID | `200` resume |
| `PATCH /resumes/{resume_id}` | editable resume fields | `200` updated resume |
| `DELETE /resumes/{resume_id}` | resume ID | `204` |

Proposed field schemas and response codes are in `docs/openapi-draft.yaml`. The initial PDF upload limit is 10 MiB. Proposed application error codes are `validation_error` (422), `invalid_credentials` (401), `invalid_refresh_token` (401), `email_already_registered` (409), `not_found` (404), `invalid_pdf` (400), `pdf_requires_ocr` (400), and `file_too_large` (413). The generic HTTP handler currently uses `http_error`; feature-specific codes are planned for the corresponding milestones.

Job matching: `POST /api/v1/job-matches` takes `resume_id` and `job_description`, returning a job with HTTP 202. Poll `GET /api/v1/jobs/{id}` for a typed result. Only the resume owner can submit or retrieve the job. A result includes `required_skills_found` (skill and exact `resume_evidence`), `required_skills_not_demonstrated`, `experience_alignment`, `recommendations`, and `interview_topics`. Provider failures are represented by safe error codes. See the running API's OpenAPI document for the complete schema.

Analysis and matching requests accept `allow_provider_fallbacks` (default `false`). Set it to `true` only after informing the user that configured fallback providers may receive the input. Legacy requests use OpenRouter alone.
