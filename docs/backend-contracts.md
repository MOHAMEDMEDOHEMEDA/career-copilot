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

## Mock interview foundation

All paths below are under `/api/v1/interviews` and require a bearer token. Every session belongs to the current user and references an owned resume. Inaccessible sessions and questions return `404`; lists return `items`, `limit`, and `offset`. Creating a session stores its job description and does not call an AI provider.

| Method and path | Request | Success |
| --- | --- | --- |
| `POST /sessions` | `resume_id`, `job_description` (1–20,000 characters) | `201` draft session |
| `GET /sessions` | `limit`, `offset` | paginated sessions |
| `GET /sessions/{id}` | session ID | owned session |
| `DELETE /sessions/{id}` | session ID | `204`, deleting questions and answers |
| `GET /sessions/{id}/questions` | `limit`, `offset` | paginated, ordered questions |
| `PUT /sessions/{id}/questions/{question_id}/answer` | `answer` (1–4,000 characters) | saved answer; prior feedback is cleared |

Resume text, job descriptions, questions, and answers are untrusted. Session data is stored until the session or its resume is deleted and is not logged.

### Interview AI output

Question generation returns exactly three bounded question prompts. Feedback assesses correctness, completeness, relevance, and clarity independently, each with a qualitative rating (`strong`, `developing`, `needs_work`, or `not_assessable`) and an explanation. It also returns strengths, improvements, and an illustrative answer. The example must not invent the candidate's experience; the app must label it as a suggestion for the user to verify. These are practice assessments, not objective employability scores. All model output must pass strict schema validation before storage.

The asynchronous API uses `POST /sessions/{id}/generation`, `POST /sessions/{id}/questions/{question_id}/feedback`, `GET /sessions/{id}/jobs/{job_id}`, and `POST /sessions/{id}/jobs/{job_id}/retry`. Requests explicitly disclose provider fallback via `allow_provider_fallbacks`, defaulting to false. Generation and feedback requests are idempotent per session or answer revision. Jobs report queued, running, completed or failed and a safe error code; they are never automatically requeued. A changed answer invalidates earlier feedback and any result generated from an older revision.

## Adaptive interview foundation

The new, separate `/api/v1/interviews/adaptive/sessions` API preserves the legacy interview contract. `POST` creates an owned session using `role`, `seniority` (`junior`, `mid`, `senior`), `interview_type` (`technical`, `behavioral`, `mixed`), optional owned `resume_id`, optional `job_description`, and up to 20 explicitly selected `skills`. A resume is optional. Selected skills are candidate-provided claims and are not verified experience. `GET` lists owned sessions with `limit` and `offset`; `GET /{id}` returns one owned session; `DELETE /{id}` deletes its adaptive interview data. Inaccessible IDs return 404. The initial status is `active`. No AI request is made during creation.

The session records a server-controlled, versioned state and starts with no assessed proficiency. Deleting an attached resume deletes its adaptive sessions and their derived data, consistent with the existing interview retention policy. User input and future retrieved references are untrusted and never instructions. Further adaptive endpoints and contracts will be added before client integration.

The evaluation component uses a versioned schema: per-criterion scores from 0 to 4 (or `null` when not assessable), an overall coaching score, answer classification, exact answer-evidence excerpts, demonstrated and missing concepts, inaccuracies, a suggested next action, and constructive feedback. These scores are approximate practice feedback, not a measure of employability. The backend independently determines the next action and validates evidence against the actual submitted answer.

Adaptive turn operations: `GET /sessions/{id}/turns` lists ordered turns; `POST /sessions/{id}/next` queues one generation job; `PUT /sessions/{id}/turns/{turn_id}/answer` saves a bounded answer; `POST /sessions/{id}/turns/{turn_id}/evaluation` queues evaluation; `GET /sessions/{id}/jobs` lists jobs for recovery, and `GET /sessions/{id}/jobs/{job_id}` retrieves job state. A failed job can be requeued explicitly via `POST /sessions/{id}/jobs/{job_id}/retry` while its input state is current. `POST /sessions/{id}/complete` is idempotent after an evaluated answer, and `GET /sessions/{id}/report` returns a basic report after completion. Generation is blocked until the prior answer has a current evaluation. Requests are owner-scoped and deduplicated per session state or answer revision. The worker records a result only if its lease and input revision remain current; failures are not automatically requeued. Fallback consent defaults to false. AI requests have a separate configurable per-user hourly limit (`ADAPTIVE_INTERVIEW_LIMIT_PER_HOUR`, default 30).

`GET /api/v1/interviews/adaptive/skill-progress` returns a paginated, owner-scoped aggregation over completed sessions, excluding topics with fewer than two scored answers. These are model-based coaching observations, not verified skill measurements. The basic report compares against an earlier completed session with the same role and seniority when each has at least two scored answers; the questions may differ. An evaluation may include references to retrieved chunks from the operator-reviewed source allowlist; the server rejects unknown IDs and attaches source snapshots. With the default empty allowlist no technical references are retrieved and no source-grounding claim is made.
# Adaptive interview example answers

Adaptive evaluation responses may include the optional `example_answer` field.
When a candidate explicitly says they do not know, the evaluator requests a short
AI-generated example and returns an unscored `not_assessable` evaluation. An
example is coaching guidance, not evidence of the candidate's proficiency.
Existing stored evaluations without this field remain valid.
# Display name

`PATCH /api/v1/auth/me/name` requires an access token and accepts
`{"display_name": "Name"}`. It updates only the authenticated account and
returns the user profile. Names are trimmed, must contain visible text, and
are limited to 100 characters. `GET /api/v1/auth/me` and registration responses
include the nullable `display_name` field; existing accounts initially have no
name. This endpoint works for password and Google accounts.
# AI usage

`GET /api/v1/ai-usage?limit=20&offset=0` requires an access token and returns
only that user's provider attempts, newest first, plus an all-time summary.
Each item contains the operation, provider, model when available, response or
failure status, reported token counts, cost when known, and cost basis. The
summary's known totals exclude unknown values; unknown attempt counts must be
shown alongside them. The endpoint does not expose prompts, answers, or tokens
used for authentication. Results before tracking was enabled are unavailable.
