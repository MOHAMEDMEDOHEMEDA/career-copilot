import Foundation
import XCTest
@testable import CareerCopilot

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
