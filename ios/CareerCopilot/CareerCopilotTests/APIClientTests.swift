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
