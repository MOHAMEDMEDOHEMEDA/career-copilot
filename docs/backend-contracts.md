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

## Career chat foundation

All routes require bearer authentication. Conversations and their messages are private to their owner; inaccessible conversation IDs return `404`. Lists use `limit` (1–100, default 20) and `offset` (default 0). These endpoints store user-written messages only; they do not yet generate AI replies.

| Method and path | Request | Successful response |
| --- | --- | --- |
| `POST /api/v1/chat/conversations` | optional `title` (1–100 characters) | `201` conversation |
| `GET /api/v1/chat/conversations` | `limit`, `offset` | `200` paginated conversations |
| `GET /api/v1/chat/conversations/{id}` | conversation ID | `200` conversation |
| `DELETE /api/v1/chat/conversations/{id}` | conversation ID | `204`; deletes its messages |
| `POST /api/v1/chat/conversations/{id}/messages` | `content` (1–4000 characters) | `201` saved user message |
| `GET /api/v1/chat/conversations/{id}/messages` | `limit`, `offset` | `200` paginated messages in conversation order |

Conversations expose `id`, `title`, `created_at`, and `updated_at`. Messages expose `id`, `conversation_id`, `sequence`, `role`, `content`, and `created_at`. Message content is untrusted, stored until the conversation is deleted, and excluded from application logs. Assistant answers use the separate job contract below, including provider disclosure and source citations.

### Planned RAG answer contract

The initial knowledge base contains project-authored career guidance, split into stable source-labelled chunks. The answer-generation service returns an `answer`, an `insufficient_information` flag, and `citations` containing stored chunk IDs, source titles, origin, and excerpts. It rejects citations that were not retrieved. If retrieval finds no relevant chunks, it returns a fixed insufficient-information answer without calling a model. Chat questions and retrieved text are untrusted. This corpus is illustrative career guidance, not a comprehensive or independently verified authority.

| Method and path | Request | Successful response |
| --- | --- | --- |
| `POST /api/v1/chat/conversations/{id}/answers` | `message_id`, `allow_provider_fallbacks` (default false) | `202` answer job; repeated requests for the same question return the existing job |
| `GET /api/v1/chat/conversations/{id}/answers/{job_id}` | owned conversation and job | `200` job status and optional assistant message ID |
| `POST /api/v1/chat/conversations/{id}/answers/{job_id}/retry` | explicit retry and fallback consent | `202` requeued failed job; active or completed jobs return `409` |

Jobs report `queued`, `running`, `completed`, or `failed`, with a safe error code and optional `answer_message_id`. Jobs are processed by the separately running worker and never automatically requeued. Assistant messages include a snapshot of `citations` (chunk ID, source ID, title, origin, and excerpt) and an `insufficient_information` flag. A question may have at most one assistant answer. All operations require ownership; only the updated app's explicit confirmation opts a job into cloud fallback.
