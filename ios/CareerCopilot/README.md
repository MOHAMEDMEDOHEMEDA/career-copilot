# Career Copilot iOS

Open `CareerCopilot.xcodeproj` in Xcode and run the `CareerCopilot` scheme on an iOS simulator. Start the backend with a configured `JWT_SECRET` and database migrations applied. Set the backend URL in the app's settings; the simulator can use `http://localhost:8000`. HTTPS is required for non-local hosts.

The current app supports account registration and sign-in, token storage in Keychain, token refresh, resume list, PDF upload, resume text viewing and editing, deletion, and server-side logout. The backend only stores extracted resume text, not the original PDF.

Google Sign-In needs an iOS OAuth client ID matching the app's bundle identifier and a web/server OAuth client ID from the same Google Cloud project. In the Xcode target build settings, set `GOOGLE_IOS_CLIENT_ID`, `GOOGLE_SERVER_CLIENT_ID`, and `GOOGLE_REVERSED_CLIENT_ID` (the iOS URL scheme shown in Google Cloud). Set the same web client ID as `GOOGLE_SERVER_CLIENT_ID` in the backend `.env`. These client IDs are configuration, not client secrets. Google sign-in has been manually exercised in the simulator; real account linking remains unverified. The current bundle ID is `com.careercopilot.spike`; choose the final bundle ID before creating production OAuth credentials.

The resume details screen offers analysis after an explicit confirmation. The backend queues a job, and the app checks its status for up to three minutes. If checking pauses, use **Check status**; leaving the screen does not cancel the server job. Previous jobs and results are available from the analysis screen after signing back in. Results reflect the resume when the job ran and are deleted with the resume. Analysis may send extracted resume text to OpenRouter and Google Gemini, or process it locally with Ollama: use synthetic resumes until privacy and retention are reviewed. Run the backend analysis worker alongside the API (for Docker, use `docker compose --profile analysis up --build`).

This is an early foundation, not a production release. Hosted deployment, full accessibility and offline handling, broader automated iOS tests, device verification, privacy disclosures, and AI chat answers still need work.

The signed-in app has Workspace, Chat, and Settings tabs. In Chat, users can create and delete conversations, ask questions, and view answers with source excerpts. The initial knowledge base is a small set of project-authored example guidance; the AI can make mistakes and retrieval has known limitations. Questions and retrieved guidance may be sent to OpenRouter and Google Gemini after confirmation, with local Ollama available as a fallback. Use synthetic data until privacy and retention have been reviewed. Conversations and messages are stored on the backend until deleted. Unsent drafts are kept in memory while signed in.

The resume details screen also offers job matching. Paste a synthetic job description and confirm before processing both inputs with the configured providers. Skill evidence is checked against the resume, but all AI output needs review. The temporary job description is deleted from the job when processing completes or its lease expires. Matching results are held in the app session; restoring matching history after relaunch is not implemented.

## Project structure

- `CareerCopilot/App`: application entry point.
- `CareerCopilot/Core/Networking`: API client and response models.
- `CareerCopilot/Core/Security`: Keychain token storage.
- `CareerCopilot/Features`: feature folders for onboarding, authentication, home, resumes, resume analysis, job matching, career chat, profile, and optional interviews. Each has `Views`, `ViewModels`, and `Models` directories.
- `CareerCopilot/DesignSystem`: shared visual tokens and components.

Views render state and forward user actions; view models own presentation state and coordinate with core services; feature models represent feature-specific data. Shared networking and token storage remain in `Core`. The empty directories are scaffolding, not implemented features. `AppViewModel` coordinates authentication and session state; `ResumeViewModel` owns resume loading and edits. The `CareerCopilotTests` target contains initial networking and view-model tests. Run them with `xcodebuild test -project CareerCopilot.xcodeproj -scheme CareerCopilot -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`, adjusting the device name to one installed locally. Generated API models and broader automated iOS coverage remain to be implemented.

Session access is coordinated so concurrent requests share one token refresh. Signing out waits for any in-progress refresh and revokes the latest refresh token before clearing the Keychain. If sign-out fails, the local session remains available so the user can retry. Resume operations ignore results from a previous session after the view model is reset.
