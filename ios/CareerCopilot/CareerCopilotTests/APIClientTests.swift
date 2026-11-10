import Foundation
import XCTest
@testable import CareerCopilot

final class OnboardingGateTests: XCTestCase {
    func testOnlyNewSignedOutUsersSeeIntroduction() {
        XCTAssertTrue(OnboardingGate.shouldPresent(hasProfile: false, completed: false, canRetryRestore: false))
        XCTAssertFalse(OnboardingGate.shouldPresent(hasProfile: true, completed: false, canRetryRestore: false))
        XCTAssertFalse(OnboardingGate.shouldPresent(hasProfile: false, completed: true, canRetryRestore: false))
        XCTAssertFalse(OnboardingGate.shouldPresent(hasProfile: false, completed: false, canRetryRestore: true))
    }
}

final class InterviewDictationTests: XCTestCase {
    func testDictationAppendsWithoutLosingOrDuplicatingExistingText() {
        XCTAssertEqual(DictationDraft.appending("second thought", to: "First thought."), "First thought. second thought")
        XCTAssertEqual(DictationDraft.appending("next line", to: "First line\n"), "First line\nnext line")
        XCTAssertEqual(DictationDraft.appending("", to: "Existing answer"), "Existing answer")
        XCTAssertEqual(DictationDraft.appending("مرحبا", to: ""), "مرحبا")
        let original = String(repeating: "x", count: 4000)
        XCTAssertEqual(DictationDraft.appending("extra", to: original).unicodeScalars.count, 4006)
    }
}

final class APIClientTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        session = nil
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testLoginSendsCredentialsAndDecodesTokens() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/auth/login")
            XCTAssertEqual(request.httpMethod, "POST")
            let body: Data
            if let directBody = request.httpBody {
                body = directBody
            } else {
                let stream = try XCTUnwrap(request.httpBodyStream)
                stream.open()
                defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 1024)
                var collected = Data()
                while stream.hasBytesAvailable {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
                    if count == 0 { break }
                    collected.append(contentsOf: bytes.prefix(count))
                }
                body = collected
            }
            let values = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
            XCTAssertEqual(values["email"], "person@example.com")
            XCTAssertEqual(values["password"], "synthetic-password")
            return (200, Data(#"{"access_token":"access","refresh_token":"refresh"}"#.utf8))
        }
        let client = APIClient(baseURL: try XCTUnwrap(URL(string: "https://example.com")), session: session)
        let tokens = try await client.login(email: "person@example.com", password: "synthetic-password")
        XCTAssertEqual(tokens.accessToken, "access")
        XCTAssertEqual(tokens.refreshToken, "refresh")
    }

    func testServerValidationMessageIsShown() async throws {
        MockURLProtocol.handler = { _ in
            (422, Data(#"{"error":{"message":"Enter a valid email address."}}"#.utf8))
        }
        let client = APIClient(baseURL: try XCTUnwrap(URL(string: "https://example.com")), session: session)
        do {
            _ = try await client.login(email: "invalid", password: "synthetic-password")
            XCTFail("Expected a validation error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Enter a valid email address.")
        }
    }

    func testProfileNameUpdateUsesAuthenticatedEndpoint() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let coordinator = SessionCoordinator(store: MemorySessionStore())
        try await coordinator.startSession(TokenPair(accessToken: "access", refreshToken: "refresh"), baseURL: url)
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/auth/me/name")
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access")
            return (200, Data(#"{"email":"person@example.com","display_name":"محمد"}"#.utf8))
        }
        let client = APIClient(baseURL: url, session: session, sessions: coordinator)
        let profile = try await client.updateDisplayName("محمد")
        XCTAssertEqual(profile.displayName, "محمد")
    }

    func testAIUsageDecodesUnknownCosts() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let coordinator = SessionCoordinator(store: MemorySessionStore())
        try await coordinator.startSession(TokenPair(accessToken: "access", refreshToken: "refresh"), baseURL: url)
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/ai-usage")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access")
            return (200, Data(#"{"summary":{"attempts":1,"known_input_tokens":12,"known_output_tokens":3,"attempts_with_unknown_tokens":0,"known_cost_usd":0,"attempts_with_unknown_cost":1},"items":[{"id":"91982D98-AC81-4C69-888B-19EE9079D5EA","operation":"chat_answer","provider":"gemini","model":"model","outcome":"response_received","input_tokens":12,"output_tokens":3,"cost_usd":null,"cost_basis":null}],"limit":20,"offset":0}"#.utf8))
        }
        let client = APIClient(baseURL: url, session: session, sessions: coordinator)
        let page = try await client.aiUsage()
        XCTAssertEqual(page.summary.attemptsWithUnknownCost, 1)
        XCTAssertNil(page.items.first?.costUSD)
    }

    func testBackendURLAllowsHTTPSAndLocalHTTPOnly() throws {
        XCTAssertNoThrow(try APIClient.configured(baseURL: "https://example.com"))
        XCTAssertNoThrow(try APIClient.configured(baseURL: "http://localhost:8000"))
        XCTAssertThrowsError(try APIClient.configured(baseURL: "http://example.com"))
        XCTAssertThrowsError(try APIClient.configured(baseURL: "https://user:password@example.com"))
        XCTAssertThrowsError(try APIClient.configured(baseURL: "not-a-url")) { error in
            XCTAssertEqual(error.localizedDescription, "Enter a valid HTTPS backend URL, or use localhost for the simulator.")
        }
    }

    func testNetworkFailuresHaveActionableMessages() async throws {
        let client = APIClient(baseURL: try XCTUnwrap(URL(string: "https://example.com")), session: session)
        for (code, expected) in [
            (URLError.notConnectedToInternet, "Can’t reach the server. Check your connection or make sure the backend is running, then try again."),
            (URLError.timedOut, "The connection timed out. Check your connection and try again.")
        ] {
            MockURLProtocol.handler = { _ in throw URLError(code) }
            do {
                _ = try await client.login(email: "person@example.com", password: "synthetic-password")
                XCTFail("Expected a connection error")
            } catch {
                XCTAssertEqual(error.localizedDescription, expected)
            }
        }
    }

    @MainActor
    func testOfflineSessionRestorationCanBeRetried() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let coordinator = SessionCoordinator(store: MemorySessionStore())
        try await coordinator.startSession(TokenPair(accessToken: "access", refreshToken: "refresh"), baseURL: url)
        let session = try XCTUnwrap(self.session)
        let model = AppViewModel(clientFactory: { _ in APIClient(baseURL: url, session: session, sessions: coordinator) })
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await model.restoreSession()
        XCTAssertFalse(model.isRestoringSession)
        XCTAssertTrue(model.canRetrySessionRestore)
        XCTAssertNil(model.profile)
        XCTAssertNotNil(model.message)

        model.message = nil
        MockURLProtocol.handler = { _ in (200, Data(#"{"email":"person@example.com"}"#.utf8)) }
        await model.restoreSession()
        XCTAssertEqual(model.profile?.email, "person@example.com")
        XCTAssertFalse(model.canRetrySessionRestore)
        XCTAssertFalse(model.isRestoringSession)
    }

    @MainActor
    func testSessionCheckCanBeRetriedWhenConfigurationFails() async {
        let model = AppViewModel(clientFactory: { _ in throw APIClient.APIError.invalidBackendURL })
        await model.restoreSession()
        XCTAssertTrue(model.canRetrySessionRestore)
        XCTAssertFalse(model.isRestoringSession)
        XCTAssertEqual(model.message, "Enter a valid HTTPS backend URL, or use localhost for the simulator.")
    }

    func testAnalysisAndMatchingRequestsIncludeFallbackConsent() async throws {
        let baseURL = try XCTUnwrap(URL(string: "https://example.com"))
        let coordinator = SessionCoordinator(store: MemorySessionStore())
        try await coordinator.startSession(TokenPair(accessToken: "access", refreshToken: "refresh"), baseURL: baseURL)
        let resumeID = UUID()
        MockURLProtocol.handler = { request in
            let body: Data
            if let data = request.httpBody { body = data }
            else {
                let stream = try XCTUnwrap(request.httpBodyStream)
                stream.open()
                defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 1024), data = Data()
                while stream.hasBytesAvailable {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
                    if count == 0 { break }
                    data.append(contentsOf: bytes.prefix(count))
                }
                body = data
            }
            let values = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(values["allow_provider_fallbacks"] as? Bool, true)
            XCTAssertEqual(values["resume_id"] as? String, resumeID.uuidString)
            let json = "{\"id\":\"00000000-0000-0000-0000-000000000001\",\"resume_id\":\"\(resumeID.uuidString)\",\"status\":\"queued\",\"result\":null,\"error_code\":null}"
            return (202, Data(json.utf8))
        }
        let client = APIClient(baseURL: baseURL, session: session, sessions: coordinator)
        _ = try await client.startAnalysis(resumeID: resumeID)
        _ = try await client.startMatch(resumeID: resumeID, description: "Synthetic role")
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.unknown) }
            let (status, data) = try handler(request)
            guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
                throw URLError(.badServerResponse)
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@MainActor
final class ResumeViewModelTests: XCTestCase {
    func testLoadAndEditResume() async {
        let resume = Resume(id: UUID(), filename: "Synthetic.pdf", text: "Original")
        let service = FakeResumeService(resume: resume)
        let model = ResumeViewModel(baseURL: "https://example.com", clientFactory: { _ in service })

        await model.loadResumes()
        XCTAssertEqual(model.resumes.first?.text, "Original")
        let saved = await model.update(resume, text: "Updated")
        XCTAssertTrue(saved)
        XCTAssertEqual(model.resumes.first?.text, "Updated")
        XCTAssertFalse(model.isLoading)
    }

    func testLoadFailureShowsErrorWithoutPretendingListIsEmpty() async {
        let service = FakeResumeService(resume: Resume(id: UUID(), filename: "Synthetic.pdf", text: "Original"))
        service.shouldFail = true
        let model = ResumeViewModel(baseURL: "https://example.com", clientFactory: { _ in service })

        await model.loadResumes()
        XCTAssertNotNil(model.loadError)
        XCTAssertFalse(model.isLoading)
        service.shouldFail = false
        await model.loadResumes()
        XCTAssertNil(model.loadError)
        XCTAssertEqual(model.resumes.count, 1)
    }

    func testUploadPassesFileToService() async throws {
        let resume = Resume(id: UUID(), filename: "Synthetic.pdf", text: "Synthetic")
        let service = FakeResumeService(resume: resume)
        let model = ResumeViewModel(baseURL: "https://example.com", clientFactory: { _ in service })
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        let contents = Data("synthetic PDF bytes".utf8)
        try contents.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        await model.upload(file)
        XCTAssertEqual(service.uploadedData, contents)
        XCTAssertEqual(model.resumes.first?.id, resume.id)
        XCTAssertNil(model.message)
    }

    func testDeleteRemovesOnlyTheSelectedResume() async {
        let resume = Resume(id: UUID(), filename: "Synthetic.pdf", text: "Original")
        let service = FakeResumeService(resume: resume)
        let model = ResumeViewModel(baseURL: "https://example.com", clientFactory: { _ in service })
        await model.loadResumes()

        await model.delete(resume)
        XCTAssertEqual(service.deletedID, resume.id)
        XCTAssertTrue(model.resumes.isEmpty)
    }

    func testFailedUpdateKeepsOriginalText() async {
        let resume = Resume(id: UUID(), filename: "Synthetic.pdf", text: "Original")
        let service = FakeResumeService(resume: resume)
        let model = ResumeViewModel(baseURL: "https://example.com", clientFactory: { _ in service })
        await model.loadResumes()
        service.shouldFail = true

        let saved = await model.update(resume, text: "Updated")
        XCTAssertFalse(saved)
        XCTAssertEqual(model.resumes.first?.text, "Original")
        XCTAssertNotNil(model.message)
    }

    func testOverlappingLoadAndResetIgnoreLateResults() async {
        let resume = Resume(id: UUID(), filename: "Synthetic.pdf", text: "Original")
        let service = DelayedResumeService(resume: resume)
        let model = ResumeViewModel(baseURL: "https://example.com", clientFactory: { _ in service })
        let first = Task { await model.loadResumes() }
        await service.waitUntilStarted()
        await model.loadResumes()
        let callCount = await service.calls
        XCTAssertEqual(callCount, 1)
        XCTAssertTrue(model.isLoading)
        model.reset()
        await service.release()
        await first.value
        XCTAssertTrue(model.resumes.isEmpty)
        XCTAssertFalse(model.isLoading)
    }
}

private final class FakeResumeService: ResumeServicing {
    var resume: Resume
    var shouldFail = false
    var deletedID: UUID?
    var uploadedData: Data?

    init(resume: Resume) { self.resume = resume }

    func resumes() async throws -> [Resume] {
        if shouldFail { throw URLError(.notConnectedToInternet) }
        return [resume]
    }

    func uploadPDF(data: Data, filename: String) async throws -> Resume {
        uploadedData = data
        return resume
    }
    func deleteResume(id: UUID) async throws { deletedID = id }
    func updateResume(id: UUID, text: String) async throws -> Resume {
        if shouldFail { throw URLError(.notConnectedToInternet) }
        resume = Resume(id: id, filename: resume.filename, text: text)
        return resume
    }
}

private actor DelayedResumeService: ResumeServicing {
    let resume: Resume
    private var continuation: CheckedContinuation<Void, Never>?
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var started = false
    private(set) var calls = 0

    init(resume: Resume) { self.resume = resume }

    func resumes() async throws -> [Resume] {
        calls += 1
        started = true
        startContinuation?.resume()
        startContinuation = nil
        await withCheckedContinuation { continuation = $0 }
        return [resume]
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startContinuation = $0 }
    }

    func release() { continuation?.resume(); continuation = nil }
    func uploadPDF(data: Data, filename: String) async throws -> Resume { resume }
    func deleteResume(id: UUID) async throws {}
    func updateResume(id: UUID, text: String) async throws -> Resume { resume }
}

final class SessionCoordinatorTests: XCTestCase {
    func testConcurrentRefreshUsesOneRequest() async throws {
        let store = MemorySessionStore()
        let coordinator = SessionCoordinator(store: store)
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        try await coordinator.startSession(TokenPair(accessToken: "old", refreshToken: "old-refresh"), baseURL: url)
        let snapshot = try await coordinator.snapshot(baseURL: url)
        let original = try XCTUnwrap(snapshot)
        let gate = RefreshGate()
        let first = Task { try await coordinator.refreshed(original, baseURL: url) { try await gate.refresh($0) } }
        await gate.waitUntilStarted()
        let second = Task { try await coordinator.refreshed(original, baseURL: url) { try await gate.refresh($0) } }
        await gate.release()
        let firstResult = try await first.value
        let secondResult = try await second.value
        let calls = await gate.calls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(firstResult.tokens.refreshToken, "new-refresh")
        XCTAssertEqual(secondResult.tokens.refreshToken, "new-refresh")
    }

    func testSignOutWaitsForRefreshAndRevokesRotatedToken() async throws {
        let coordinator = SessionCoordinator(store: MemorySessionStore())
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        try await coordinator.startSession(TokenPair(accessToken: "old", refreshToken: "old-refresh"), baseURL: url)
        let snapshot = try await coordinator.snapshot(baseURL: url)
        let original = try XCTUnwrap(snapshot)
        let gate = RefreshGate()
        let revoked = RevokedToken()
        let refresh = Task { try await coordinator.refreshed(original, baseURL: url) { try await gate.refresh($0) } }
        await gate.waitUntilStarted()
        let logout = Task { try await coordinator.signOut(baseURL: url) { await revoked.set($0) } }
        var signingOut = false
        for _ in 0..<1_000 {
            if try await coordinator.snapshot(baseURL: url) == nil { signingOut = true; break }
            await Task.yield()
        }
        XCTAssertTrue(signingOut)
        await gate.release()
        try await logout.value
        do {
            _ = try await refresh.value
            XCTFail("A refresh started before logout must not restore the session")
        } catch {}
        let token = await revoked.value
        let remaining = try await coordinator.snapshot(baseURL: url)
        XCTAssertEqual(token, "new-refresh")
        XCTAssertNil(remaining)
    }

    func testOldRefreshCannotReplaceANewSession() async throws {
        let coordinator = SessionCoordinator(store: MemorySessionStore())
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        try await coordinator.startSession(TokenPair(accessToken: "first", refreshToken: "first-refresh"), baseURL: url)
        let snapshot = try await coordinator.snapshot(baseURL: url)
        let original = try XCTUnwrap(snapshot)
        let gate = RefreshGate()
        let refresh = Task { try await coordinator.refreshed(original, baseURL: url) { try await gate.refresh($0) } }
        await gate.waitUntilStarted()
        try await coordinator.startSession(TokenPair(accessToken: "second", refreshToken: "second-refresh"), baseURL: url)
        await gate.release()
        do {
            _ = try await refresh.value
            XCTFail("The earlier session must not overwrite the new session")
        } catch {}
        let current = try await coordinator.snapshot(baseURL: url)
        XCTAssertEqual(current?.tokens.refreshToken, "second-refresh")
    }
}

private final class MemorySessionStore: SessionTokenStoring {
    private var tokens: TokenPair?
    func load(baseURL: URL) throws -> TokenPair? { tokens }
    func save(_ tokens: TokenPair, baseURL: URL) throws { self.tokens = tokens }
    func clear() throws { tokens = nil }
}

private actor RefreshGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var started = false
    private(set) var calls = 0

    func refresh(_ token: String) async throws -> TokenPair {
        calls += 1
        started = true
        startContinuation?.resume()
        startContinuation = nil
        await withCheckedContinuation { continuation = $0 }
        return TokenPair(accessToken: "new", refreshToken: "new-refresh")
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startContinuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor RevokedToken {
    private(set) var value: String?
    func set(_ token: String) { value = token }
}

@MainActor
final class AnalysisViewModelTests: XCTestCase {
    func testHistoryRestoresACompletedResult() async {
        let resumeID = UUID(), jobID = UUID()
        let result = ResumeAnalysis(summary: "Saved synthetic result", technicalSkills: [], softSkills: [], experience: [], education: [], strengths: [], improvementSuggestions: [], missingOrUnclearInformation: [], bulletRewrites: [])
        let saved = AnalysisJob(id: jobID, resumeID: resumeID, status: .completed, result: result)
        let service = FakeAnalysisService(jobs: [], history: [saved])
        let model = AnalysisViewModel(resumeID: resumeID, service: service, wait: {})
        await model.loadHistory()
        guard let job = model.history.first else { return XCTFail("Expected saved job") }
        model.select(job)
        guard case .completed(let analysis) = model.state else { return XCTFail("Expected saved result") }
        XCTAssertEqual(analysis.summary, "Saved synthetic result")
        let submissions = await service.submissions
        XCTAssertEqual(submissions, 0)
    }

    func testQueuedJobReachesCompletedWithoutResubmitting() async {
        let resumeID = UUID(), jobID = UUID()
        let result = ResumeAnalysis(summary: "Synthetic summary", technicalSkills: ["Swift"], softSkills: [], experience: [], education: [], strengths: [], improvementSuggestions: [], missingOrUnclearInformation: [], bulletRewrites: [])
        let service = FakeAnalysisService(jobs: [
            AnalysisJob(id: jobID, resumeID: resumeID, status: .queued, result: nil),
            AnalysisJob(id: jobID, resumeID: resumeID, status: .running, result: nil),
            AnalysisJob(id: jobID, resumeID: resumeID, status: .completed, result: result)
        ])
        let model = AnalysisViewModel(resumeID: resumeID, service: service, wait: {})
        await model.start()
        await model.poll()
        guard case .completed(let analysis) = model.state else { return XCTFail("Expected completed analysis") }
        XCTAssertEqual(analysis.summary, "Synthetic summary")
        let submissions = await service.submissions
        XCTAssertEqual(submissions, 1)
    }

    func testPollingStopsAndCanBeCheckedAgainWithoutSubmitting() async {
        let resumeID = UUID(), jobID = UUID()
        let job = AnalysisJob(id: jobID, resumeID: resumeID, status: .queued, result: nil)
        let service = FakeAnalysisService(jobs: [job, job, job])
        let model = AnalysisViewModel(resumeID: resumeID, service: service, maxPolls: 1, wait: {})
        await model.start()
        await model.poll()
        guard case .paused = model.state else { return XCTFail("Expected polling to pause") }
        model.checkStatus()
        await model.poll()
        let submissions = await service.submissions
        let checks = await service.checks
        XCTAssertEqual(submissions, 1)
        XCTAssertEqual(checks, 2)
    }

    func testUnexpectedJobDoesNotDisplayAnotherResumeResult() async {
        let resumeID = UUID(), jobID = UUID()
        let service = FakeAnalysisService(jobs: [
            AnalysisJob(id: jobID, resumeID: resumeID, status: .queued, result: nil),
            AnalysisJob(id: jobID, resumeID: UUID(), status: .completed, result: nil)
        ])
        let model = AnalysisViewModel(resumeID: resumeID, service: service, wait: {})
        await model.start()
        await model.poll()
        guard case .paused = model.state else { return XCTFail("Expected unexpected job to be rejected") }
    }

    func testBackendResultDecodesSnakeCaseFields() throws {
        let data = Data(#"{"id":"00000000-0000-0000-0000-000000000001","resume_id":"00000000-0000-0000-0000-000000000002","status":"completed","result":{"summary":"Synthetic","technical_skills":["Swift"],"soft_skills":[],"experience":[],"education":[],"strengths":[],"improvement_suggestions":["Clarify"],"missing_or_unclear_information":[],"bullet_rewrites":[{"original":"Built app","rewrite":"Built a Swift app"}]}}"#.utf8)
        let job = try JSONDecoder().decode(AnalysisJob.self, from: data)
        XCTAssertEqual(job.result?.technicalSkills, ["Swift"])
        XCTAssertEqual(job.result?.improvementSuggestions, ["Clarify"])
        XCTAssertEqual(job.result?.bulletRewrites.first?.rewrite, "Built a Swift app")
    }
}

private actor FakeAnalysisService: AnalysisServicing {
    private var jobs: [AnalysisJob]
    private let history: [AnalysisJob]
    private(set) var submissions = 0
    private(set) var checks = 0
    init(jobs: [AnalysisJob], history: [AnalysisJob] = []) { self.jobs = jobs; self.history = history }
    func startAnalysis(resumeID: UUID) async throws -> AnalysisJob {
        submissions += 1
        return jobs.removeFirst()
    }
    func analysisJob(id: UUID) async throws -> AnalysisJob {
        checks += 1
        return jobs.removeFirst()
    }
    func analysisHistory(resumeID: UUID, offset: Int) async throws -> [AnalysisJob] { history }
}

@MainActor
final class JobMatchViewModelTests: XCTestCase {
    func testDescriptionLimitCountsUnicodeScalars() async {
        let service = FakeMatchService(jobs: [])
        let model = JobMatchViewModel(resumeID: UUID(), service: service, wait: {})
        model.description = String(repeating: "👨‍👩‍👧‍👦", count: 3000)
        XCTAssertGreaterThan(model.description.unicodeScalars.count, 20_000)
        await model.start()
        let submissions = await service.submissions
        XCTAssertEqual(submissions, 0)
    }

    func testUnsupportedEvidenceExplainsWhyMatchWasRejected() async {
        let resumeID = UUID(), jobID = UUID()
        let service = FakeMatchService(jobs: [
            MatchJob(id: jobID, resumeID: resumeID, status: .queued, result: nil, errorCode: nil),
            MatchJob(id: jobID, resumeID: resumeID, status: .failed, result: nil, errorCode: "unsupported_evidence")
        ])
        let model = JobMatchViewModel(resumeID: resumeID, service: service, wait: {})
        model.description = "Synthetic role"
        await model.start()
        await model.poll()
        guard case .failed(let message) = model.state else { return XCTFail("Expected a failure") }
        XCTAssertTrue(message.contains("quote"))
    }

    func testMatchFinishesWithoutResubmitting() async {
        let resumeID = UUID(), jobID = UUID()
        let result = JobMatch(requiredSkillsFound: [.init(skill: "Swift", resumeEvidence: "Built with Swift")], requiredSkillsNotDemonstrated: ["Python"], experienceAlignment: "Relevant app project", recommendations: [], interviewTopics: [])
        let service = FakeMatchService(jobs: [
            MatchJob(id: jobID, resumeID: resumeID, status: .queued, result: nil, errorCode: nil),
            MatchJob(id: jobID, resumeID: resumeID, status: .completed, result: result, errorCode: nil)
        ])
        let model = JobMatchViewModel(resumeID: resumeID, service: service, wait: {})
        model.description = "Synthetic developer role"
        await model.start()
        await model.poll()
        guard case .completed(let match) = model.state else { return XCTFail("Expected match result") }
        XCTAssertEqual(match.requiredSkillsFound.first?.resumeEvidence, "Built with Swift")
        let submissions = await service.submissions
        XCTAssertEqual(submissions, 1)
    }

    func testEmptyDescriptionDoesNotSubmit() async {
        let service = FakeMatchService(jobs: [])
        let model = JobMatchViewModel(resumeID: UUID(), service: service, wait: {})
        await model.start()
        let submissions = await service.submissions
        XCTAssertEqual(submissions, 0)
    }
}

private actor FakeMatchService: JobMatchServicing {
    private var jobs: [MatchJob]
    private(set) var submissions = 0
    init(jobs: [MatchJob]) { self.jobs = jobs }
    func startMatch(resumeID: UUID, description: String) async throws -> MatchJob {
        submissions += 1
        return jobs.removeFirst()
    }
    func matchJob(id: UUID) async throws -> MatchJob { jobs.removeFirst() }
}

@MainActor
final class ChatViewModelTests: XCTestCase {
    func testActiveAnswerCanResumeAfterLeavingChat() async {
        let conversation = ChatConversation(id: UUID(), title: "Synthetic", createdAt: "", updatedAt: "")
        let service = FakeChatService(conversation: conversation)
        let model = ChatViewModel(clientFactory: { _ in service })
        await model.open(conversation)
        model.draft = "Synthetic question"
        guard let question = await model.send(conversationID: conversation.id) else { return XCTFail("Expected question") }
        await model.requestAnswer(conversationID: conversation.id, questionID: question.id)
        let jobID = model.answerJob?.id
        model.close(conversationID: conversation.id)
        await model.open(conversation)
        XCTAssertEqual(model.answerJob?.id, jobID)
        XCTAssertNotNil(model.answerPollingToken)
        await model.pollAnswer(conversationID: conversation.id)
        XCTAssertTrue(model.hasAnswer(for: question.id))
    }

    func testQuestionLimitCountsUnicodeScalars() async {
        let conversation = ChatConversation(id: UUID(), title: "Synthetic", createdAt: "", updatedAt: "")
        let service = FakeChatService(conversation: conversation)
        let model = ChatViewModel(clientFactory: { _ in service })
        await model.open(conversation)
        model.draft = String(repeating: "👨‍👩‍👧‍👦", count: 600)
        XCTAssertGreaterThan(model.draft.unicodeScalars.count, 4000)
        await model.send(conversationID: conversation.id)
        let attempts = await service.sendAttempts
        XCTAssertEqual(attempts, 0)
    }

    func testAnswerJobLoadsCitedAssistantReply() async {
        let conversation = ChatConversation(id: UUID(), title: "Synthetic", createdAt: "", updatedAt: "")
        let service = FakeChatService(conversation: conversation)
        let model = ChatViewModel(clientFactory: { _ in service })
        await model.open(conversation)
        model.draft = "Synthetic question"
        guard let question = await model.send(conversationID: conversation.id) else { return XCTFail("Expected question") }
        await model.requestAnswer(conversationID: conversation.id, questionID: question.id)
        await model.pollAnswer(conversationID: conversation.id)
        XCTAssertEqual(model.answerJob?.status, .completed)
        XCTAssertTrue(model.hasAnswer(for: question.id))
        XCTAssertEqual(model.messages.last?.citations?.first?.title, "Synthetic source")
    }

    func testDraftSurvivesLeavingAndReturningToConversation() async {
        let conversation = ChatConversation(id: UUID(), title: "Synthetic", createdAt: "", updatedAt: "")
        let service = FakeChatService(conversation: conversation)
        let model = ChatViewModel(clientFactory: { _ in service })
        await model.open(conversation)
        model.draft = "Unfinished synthetic question"
        model.close(conversationID: conversation.id)
        await model.open(conversation)
        XCTAssertEqual(model.draft, "Unfinished synthetic question")
        model.reset()
        await model.open(conversation)
        XCTAssertEqual(model.draft, "")
    }

    func testSavesMessageAndClearsPrivateStateOnReset() async {
        let conversation = ChatConversation(id: UUID(), title: "Synthetic", createdAt: "", updatedAt: "")
        let service = FakeChatService(conversation: conversation)
        let model = ChatViewModel(clientFactory: { _ in service })
        await model.open(conversation)
        model.draft = "Synthetic question"
        await model.send(conversationID: conversation.id)
        XCTAssertEqual(model.messages.first?.content, "Synthetic question")
        XCTAssertEqual(model.draft, "")
        model.reset()
        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertTrue(model.conversations.isEmpty)
        XCTAssertFalse(model.hasLoadedMessages)
    }

    func testUncertainSendRequiresRefreshBeforeAnotherSubmission() async {
        let conversation = ChatConversation(id: UUID(), title: "Synthetic", createdAt: "", updatedAt: "")
        let service = FakeChatService(conversation: conversation)
        let model = ChatViewModel(clientFactory: { _ in service })
        await model.open(conversation)
        await service.setFailSend(true)
        model.draft = "Synthetic question"
        await model.send(conversationID: conversation.id)
        XCTAssertTrue(model.needsRefreshBeforeSending)
        await model.send(conversationID: conversation.id)
        let attempts = await service.sendAttempts
        XCTAssertEqual(attempts, 1)
        await service.setFailSend(false)
        await model.loadMessages(conversationID: conversation.id)
        XCTAssertFalse(model.needsRefreshBeforeSending)
        await model.send(conversationID: conversation.id)
        XCTAssertEqual(model.messages.count, 1)
    }
}

private actor FakeChatService: ChatServicing {
    let conversation: ChatConversation
    private var messages: [ChatMessage] = []
    private var failSend = false
    private(set) var sendAttempts = 0
    private let answerJobID = UUID()
    private var answerQuestionID: UUID?
    init(conversation: ChatConversation) { self.conversation = conversation }
    func setFailSend(_ value: Bool) { failSend = value }
    func conversations(offset: Int) async throws -> ChatPage<ChatConversation> { ChatPage(items: [conversation], limit: 20, offset: offset) }
    func createConversation(title: String) async throws -> ChatConversation { conversation }
    func deleteConversation(id: UUID) async throws {}
    func chatMessages(conversationID: UUID, offset: Int) async throws -> ChatPage<ChatMessage> { ChatPage(items: messages, limit: 100, offset: offset) }
    func saveChatMessage(conversationID: UUID, content: String) async throws -> ChatMessage {
        sendAttempts += 1
        if failSend { throw URLError(.notConnectedToInternet) }
        let message = ChatMessage(id: UUID(), conversationID: conversationID, sequence: messages.count + 1, role: .user, content: content, createdAt: "")
        messages.append(message)
        return message
    }
    func requestChatAnswer(conversationID: UUID, questionID: UUID) async throws -> ChatAnswerJob {
        answerQuestionID = questionID
        return ChatAnswerJob(id: answerJobID, conversationID: conversationID, questionID: questionID, status: .queued, answerMessageID: nil, errorCode: nil)
    }
    func chatAnswerJob(conversationID: UUID, jobID: UUID) async throws -> ChatAnswerJob {
        guard let questionID = answerQuestionID else { throw URLError(.badServerResponse) }
        let citation = ChatCitation(chunkID: "source:0", sourceID: "source", title: "Synthetic source", origin: "Test", excerpt: "Synthetic evidence")
        var message = ChatMessage(id: UUID(), conversationID: conversationID, sequence: messages.count + 1, role: .assistant, content: "Synthetic answer", createdAt: "")
        message.replyToID = questionID
        message.citations = [citation]
        messages.append(message)
        return ChatAnswerJob(id: jobID, conversationID: conversationID, questionID: questionID, status: .completed, answerMessageID: message.id, errorCode: nil)
    }
    func retryChatAnswer(conversationID: UUID, jobID: UUID) async throws -> ChatAnswerJob { throw URLError(.unsupportedURL) }
}

@MainActor
final class InterviewViewModelTests: XCTestCase {
    func testLoadsAnswersAndClearsPrivateDataOnReset() async {
        let id = UUID()
        let service = FakeInterviewService(sessionID: id)
        let model = InterviewViewModel(clientFactory: { _ in service })
        await model.loadSessions()
        await model.open(id)
        XCTAssertTrue(model.hasLoadedQuestions)
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertEqual(model.questions.count, 1)
        let saved = await model.save(sessionID: id, questionID: model.questions[0].id, answer: "Synthetic answer")
        XCTAssertTrue(saved)
        XCTAssertEqual(model.questions[0].answer, "Synthetic answer")
        model.reset()
        XCTAssertTrue(model.questions.isEmpty)
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertFalse(model.hasLoadedQuestions)
    }

    func testChecksInterruptedInterviewJobWithoutCreatingAnotherRequest() async {
        let id = UUID()
        let service = FakeInterviewService(sessionID: id)
        let model = InterviewViewModel(clientFactory: { _ in service })
        await model.open(id)
        await model.request(sessionID: id, questionID: nil)
        XCTAssertEqual(model.job?.status, .queued)
        XCTAssertNotNil(model.error)
        await model.checkStatus(sessionID: id)
        XCTAssertEqual(model.job?.status, .completed)
        XCTAssertNil(model.error)
        let requests = await service.jobRequests
        XCTAssertEqual(requests, 1)
    }

    func testReopeningSessionRecoversPendingJob() async {
        let id = UUID()
        let service = FakeInterviewService(sessionID: id)
        let model = InterviewViewModel(clientFactory: { _ in service })
        await model.open(id)
        await model.request(sessionID: id, questionID: nil)
        XCTAssertEqual(model.job?.status, .queued)
        await model.open(id)
        XCTAssertEqual(model.job?.status, .completed)
        XCTAssertNil(model.error)
        let requests = await service.jobRequests
        XCTAssertEqual(requests, 1)
        model.reset()
        XCTAssertNil(model.job)
    }

    func testOldRequestDoesNotClearNewSessionError() async {
        let first = UUID(), second = UUID()
        let service = DelayedInterviewService(failingSession: second)
        let model = InterviewViewModel(clientFactory: { _ in service })
        await model.open(first)
        let request = Task { await model.request(sessionID: first, questionID: nil) }
        await service.waitUntilRequested()
        await model.open(second)
        XCTAssertNotNil(model.error)
        await service.finishRequest()
        await request.value
        XCTAssertNotNil(model.error)
        XCTAssertFalse(model.hasLoadedQuestions)
    }
}

private actor DelayedInterviewService: InterviewServicing {
    let failingSession: UUID
    private var requestContinuation: CheckedContinuation<InterviewJob, Never>?
    private var requestStarted: CheckedContinuation<Void, Never>?
    private var requestedSession: UUID?
    init(failingSession: UUID) { self.failingSession = failingSession }
    func waitUntilRequested() async {
        if requestedSession != nil { return }
        await withCheckedContinuation { requestStarted = $0 }
    }
    func finishRequest() {
        guard let requestedSession else { return }
        requestContinuation?.resume(returning: InterviewJob(id: UUID(), sessionID: requestedSession, questionID: nil, status: .queued, errorCode: nil))
        requestContinuation = nil
    }
    func interviews(offset: Int) async throws -> ChatPage<InterviewSession> { ChatPage(items: [], limit: 20, offset: offset) }
    func createInterview(resumeID: UUID, description: String) async throws -> InterviewSession { throw URLError(.unsupportedURL) }
    func deleteInterview(id: UUID) async throws {}
    func interviewQuestions(sessionID: UUID) async throws -> ChatPage<InterviewQuestion> {
        if sessionID == failingSession { throw URLError(.notConnectedToInternet) }
        return ChatPage(items: [], limit: 100, offset: 0)
    }
    func saveInterviewAnswer(sessionID: UUID, questionID: UUID, answer: String) async throws -> InterviewQuestion { throw URLError(.unsupportedURL) }
    func requestInterviewJob(sessionID: UUID, questionID: UUID?) async throws -> InterviewJob {
        requestedSession = sessionID
        requestStarted?.resume(); requestStarted = nil
        return await withCheckedContinuation { requestContinuation = $0 }
    }
    func interviewJob(sessionID: UUID, jobID: UUID) async throws -> InterviewJob { throw URLError(.unsupportedURL) }
    func retryInterviewJob(sessionID: UUID, jobID: UUID) async throws -> InterviewJob { throw URLError(.unsupportedURL) }
}

@MainActor
final class AdaptiveInterviewViewModelTests: XCTestCase {
    func testReopeningRestoresPendingJobWithoutStartingAnotherRequest() async {
        let id = UUID()
        let service = FakeAdaptiveInterviewService(sessionID: id)
        let model = AdaptiveInterviewViewModel(factory: { _ in service })
        await model.open(id)
        XCTAssertEqual(model.job?.status, .completed)
        XCTAssertEqual(model.turns.count, 1)
        let requested = await service.generatedRequests
        XCTAssertEqual(requested, 0)
    }
}

private actor FakeAdaptiveInterviewService: AdaptiveInterviewServicing {
    let interview: AdaptiveSession
    let queued: AdaptiveJob
    private(set) var generatedRequests = 0
    init(sessionID: UUID) {
        interview = AdaptiveSession(id: sessionID, role: "Synthetic developer", seniority: "mid", status: "active", interviewType: "technical", resumeID: nil, currentDifficulty: 3, stateVersion: 0)
        queued = AdaptiveJob(id: UUID(), sessionID: sessionID, turnID: nil, kind: "next", status: .queued, errorCode: nil, stateVersion: 0)
    }
    func adaptiveSessions(offset: Int) async throws -> ChatPage<AdaptiveSession> { ChatPage(items: [interview], limit: 20, offset: offset) }
    func createAdaptiveSession(role: String, seniority: String, interviewType: String, resumeID: UUID?, description: String, skills: [String]) async throws -> AdaptiveSession { interview }
    func adaptiveSession(id: UUID) async throws -> AdaptiveSession { interview }
    func deleteAdaptiveSession(id: UUID) async throws {}
    func adaptiveTurns(sessionID: UUID) async throws -> ChatPage<AdaptiveTurn> { ChatPage(items: [AdaptiveTurn(id: UUID(), sessionID: sessionID, sequence: 1, difficulty: 3, topic: "Swift", prompt: "Synthetic question?", answer: nil, evaluation: nil)], limit: 100, offset: 0) }
    func adaptiveJobs(sessionID: UUID) async throws -> ChatPage<AdaptiveJob> { ChatPage(items: [queued], limit: 100, offset: 0) }
    func saveAdaptiveAnswer(sessionID: UUID, turnID: UUID, answer: String) async throws -> AdaptiveTurn { throw URLError(.unsupportedURL) }
    func requestAdaptiveJob(sessionID: UUID, turnID: UUID?) async throws -> AdaptiveJob { generatedRequests += 1; return queued }
    func adaptiveJob(sessionID: UUID, jobID: UUID) async throws -> AdaptiveJob { AdaptiveJob(id: jobID, sessionID: sessionID, turnID: nil, kind: "next", status: .completed, errorCode: nil, stateVersion: 0) }
    func retryAdaptiveJob(sessionID: UUID, jobID: UUID) async throws -> AdaptiveJob { throw URLError(.unsupportedURL) }
    func completeAdaptiveSession(sessionID: UUID) async throws -> AdaptiveSession { throw URLError(.unsupportedURL) }
    func adaptiveReport(sessionID: UUID) async throws -> AdaptiveReport { throw URLError(.unsupportedURL) }
    func adaptiveProgress(offset: Int) async throws -> ChatPage<AdaptiveTopicProgress> { ChatPage(items: [], limit: 100, offset: offset) }
}

private actor FakeInterviewService: InterviewServicing {
    let interview: InterviewSession
    var question: InterviewQuestion
    private let jobID = UUID()
    private var statusChecks = 0
    private(set) var jobRequests = 0
    init(sessionID: UUID) {
        interview = InterviewSession(id: sessionID, resumeID: UUID(), jobDescription: "Synthetic role", status: "ready")
        question = InterviewQuestion(id: UUID(), sessionID: sessionID, sequence: 1, prompt: "Synthetic question?", answer: nil, feedback: nil)
    }
    func interviews(offset: Int) async throws -> ChatPage<InterviewSession> { ChatPage(items: [interview], limit: 20, offset: offset) }
    func createInterview(resumeID: UUID, description: String) async throws -> InterviewSession { interview }
    func deleteInterview(id: UUID) async throws {}
    func interviewQuestions(sessionID: UUID) async throws -> ChatPage<InterviewQuestion> { ChatPage(items: [question], limit: 100, offset: 0) }
    func saveInterviewAnswer(sessionID: UUID, questionID: UUID, answer: String) async throws -> InterviewQuestion {
        question = InterviewQuestion(id: question.id, sessionID: sessionID, sequence: 1, prompt: question.prompt, answer: answer, feedback: nil)
        return question
    }
    func requestInterviewJob(sessionID: UUID, questionID: UUID?) async throws -> InterviewJob {
        jobRequests += 1
        return InterviewJob(id: jobID, sessionID: sessionID, questionID: questionID, status: .queued, errorCode: nil)
    }
    func interviewJob(sessionID: UUID, jobID: UUID) async throws -> InterviewJob {
        statusChecks += 1
        if statusChecks == 1 { throw URLError(.notConnectedToInternet) }
        return InterviewJob(id: jobID, sessionID: sessionID, questionID: nil, status: .completed, errorCode: nil)
    }
    func retryInterviewJob(sessionID: UUID, jobID: UUID) async throws -> InterviewJob { throw URLError(.unsupportedURL) }
}
