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
