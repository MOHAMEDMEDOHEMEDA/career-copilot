# Career Copilot iOS

A SwiftUI iOS app for career preparation, backed by the Career Copilot FastAPI service. It uses feature-oriented MVVM, async/await, URLSession, and Keychain token storage. The project currently targets iOS 17 and later.

## Run locally

1. Follow the [backend setup](../../backend/career-copilot-backend/README.md), including migrations and the analysis worker. Configure Ollama and index the knowledge corpus to use knowledge-backed chat.
2. Open `CareerCopilot.xcodeproj` in Xcode and select the `CareerCopilot` scheme and an available simulator.
3. Run the app. In Settings, set the backend URL if needed. The simulator can use `http://localhost:8000`; non-local hosts require HTTPS.

In Settings, choose English, Arabic, or the system language. Arabic uses a right-to-left layout. The interface has Arabic translations for its main screens; some dynamic status and server messages may still appear in English. User-entered text and AI-generated content retain their original language. iOS permission prompts follow the device's language settings.

A physical iPhone cannot use its own `localhost` to reach your Mac. It needs a reachable, appropriately configured backend URL. A hosted deployment and real-device verification are still needed for release.

## Google Sign-In

Google Sign-In requires an iOS OAuth client ID matching the app bundle identifier and a web/server OAuth client ID from the same Google Cloud project. Configure `GOOGLE_IOS_CLIENT_ID`, `GOOGLE_SERVER_CLIENT_ID`, and `GOOGLE_REVERSED_CLIENT_ID` in the Xcode target build settings, and set the same web client ID as `GOOGLE_SERVER_CLIENT_ID` in the backend `.env`. These client IDs are configuration, not client secrets.

The current bundle ID is `com.careercopilot.spike`; choose the final bundle ID and corresponding OAuth configuration before release. Google sign-in has been manually exercised in the simulator. Linking Google to an existing email/password account still needs real-account verification.

## Features

- Onboarding, account registration, email/password and Google sign-in, token refresh, and logout.
- **Workspace:** PDF resume upload, extracted-text viewing and editing, deletion, resume analysis, and job matching. The backend stores extracted resume text, not the original PDF. Scanned PDFs without extractable text require OCR, which is not implemented.
- **Chat:** create and delete conversations, ask career questions, and view answers with source excerpts. The project-authored corpus is limited and answers can be inaccurate.
- **Practice:** standard and adaptive interviews. Adaptive sessions can use a selected role, seniority, skills, and optional resume; they support question and answer turns, feedback, session recovery, reports, and topic progress. Submit an answer to request feedback automatically, or choose the “I don't know” option for an unscored example answer.
- **Settings:** account and backend configuration.
- **AI usage:** review recorded provider attempts, available token counts, and
  known or estimated costs in Settings. Unknown costs and incomplete totals are
  identified; tracking begins only after the feature is enabled.

Adaptive answer dictation requests microphone and speech-recognition permission and requires on-device recognition for the selected app language. Availability depends on the device and locale. Users can review and edit the transcription before submitting it.

AI-generated feedback and example answers are approximate study guidance, not verified assessments. The app discloses provider use before AI requests. Depending on the request, selected resume excerpts, job details, questions, and answers may be sent to OpenRouter or Google Gemini or processed by local Ollama. Google’s free tier may use content to improve products. Use synthetic data until privacy and retention have been reviewed.

## Project structure

- `CareerCopilot/App` — application entry point.
- `CareerCopilot/Core` — networking and Keychain token storage.
- `CareerCopilot/Features` — onboarding, authentication, home, resumes, analysis, job matching, chat, profile, and interviews.
- `CareerCopilot/DesignSystem` — shared visual styles and components.
- `CareerCopilotTests` — networking and view-model tests.

Views render state and forward user actions; view models coordinate presentation state and services. The networking layer uses manually maintained API models; generated models have not been implemented.

## Checks

Run the iOS tests with an installed simulator, adjusting the device name as needed:

```bash
xcodebuild test -project CareerCopilot.xcodeproj -scheme CareerCopilot -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

For a build without running tests:

```bash
xcodebuild build -project CareerCopilot.xcodeproj -scheme CareerCopilot -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

## Known limitations

This is not a production release. Hosted deployment, account deletion, privacy and retention review, a real-device run, a complete accessibility audit, broader iOS tests, and offline access to saved server data remain. Job-matching results are held in the app session; restoring matching history after relaunch is not implemented. Technical interview references require explicit backend review and configuration. AI feedback and source citations still require quality evaluation.
