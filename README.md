# Career Copilot AI

Career Copilot AI is a portfolio project for practicing career preparation. It combines a SwiftUI iOS app with a FastAPI backend for resume analysis, job matching, cited career chat, and mock interviews. AI feedback is coaching guidance and may be inaccurate; it is not a measure of employability.

## What is included

- Email/password and Google sign-in, resume PDF upload and extracted-text editing.
- Resume analysis and job matching with asynchronous jobs.
- Career chat using a project-authored knowledge corpus and source excerpts.
- Standard and adaptive mock interviews, including answer feedback, reports, and on-device dictation when supported.
- An adaptive interview option to request an example answer when the candidate does not know the answer.

The app is a local-development project, not a production release. Use synthetic resumes and questions until provider privacy, data retention, and security have been reviewed. Cloud AI providers may process submitted content; the app displays a disclosure before AI requests.

## Get started

1. Follow the [backend README](backend/career-copilot-backend/README.md) to configure `.env`, start PostgreSQL, the API and the worker, and apply migrations.
2. For knowledge-backed chat, install Ollama and its embedding model and index the corpus as described in the backend README.
3. Follow the [iOS README](ios/CareerCopilot/README.md) to configure sign-in and run the app in Xcode. The iOS simulator can use `http://localhost:8000`.

The API exposes interactive documentation at `http://localhost:8000/docs` and a health endpoint at `http://localhost:8000/health`. Keep credentials in local configuration; do not commit `.env` or real resumes.

## Repository

- [`ios/CareerCopilot/`](ios/CareerCopilot/) — SwiftUI app, feature-specific MVVM code, and iOS tests.
- [`backend/career-copilot-backend/`](backend/career-copilot-backend/) — FastAPI service, database migrations, worker, knowledge corpus, and backend tests.
- [`docs/`](docs/) — [specification](docs/spec.md), [architecture](docs/architecture.md), and [backend contracts](docs/backend-contracts.md).

## Current limitations

The backend has not been deployed as part of the local setup. Account deletion, a complete privacy review, a real-device release check, broader accessibility and offline testing, and a deployment guide remain to be completed. Technical interview retrieval only uses explicitly reviewed and configured sources; none are enabled by default. The corpus and AI evaluations need more quality review. See the component READMEs for setup details and additional limitations.
