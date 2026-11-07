import Foundation

struct Profile: Decodable {
    let email: String
}

struct Resume: Decodable, Identifiable {
    let id: UUID
    let filename: String
    let text: String
}

private struct ResumePage: Decodable {
    let items: [Resume]
}

private struct AnalysisRequest: Encodable {
    let resume_id: String
    let allow_provider_fallbacks = true
}

private struct MatchRequest: Encodable {
    let resume_id: String
    let job_description: String
    let allow_provider_fallbacks = true
}

private struct ErrorEnvelope: Decodable {
    struct Detail: Decodable { let message: String }
    let error: Detail
}

struct APIClient {
    let baseURL: URL
    var session: URLSession = .shared
    var sessions: SessionCoordinator = .shared

    static func configured(baseURL: String) throws -> APIClient {
        guard let url = URL(string: baseURL), let scheme = url.scheme,
              let host = url.host,
              scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw APIError.invalidBackendURL
        }
        return APIClient(baseURL: url)
    }

    func login(email: String, password: String) async throws -> TokenPair {
        try await post("api/v1/auth/login", body: ["email": email, "password": password])
    }

    func register(email: String, password: String) async throws {
        let _: Profile = try await post("api/v1/auth/register", body: ["email": email, "password": password])
    }

    func googleLogin(idToken: String) async throws -> TokenPair {
        try await post("api/v1/auth/google", body: ["id_token": idToken])
    }

    func linkGoogle(idToken: String) async throws {
        let body = try JSONEncoder().encode(["id_token": idToken])
        let (data, response) = try await authorizedRequest(
            path: "api/v1/auth/google/link", method: "POST", body: body, contentType: "application/json"
        )
        try validate(response, data: data)
    }

    func profile() async throws -> Profile {
        try await authenticated(path: "api/v1/auth/me")
    }

    func resumes() async throws -> [Resume] {
        var items: [Resume] = []
        while true {
            let page: ResumePage = try await authenticated(path: "api/v1/resumes?limit=100&offset=\(items.count)")
            items.append(contentsOf: page.items)
            if page.items.count < 100 { return items }
        }
    }

    func uploadPDF(data: Data, filename: String) async throws -> Resume {
        guard data.count <= 10 * 1024 * 1024 else { throw APIError.fileTooLarge }
        let boundary = "Boundary-\(UUID().uuidString)"
        let safeFilename = filename.replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "\r", with: "_").replacingOccurrences(of: "\n", with: "_")
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeFilename)\"\r\nContent-Type: application/pdf\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return try await authenticated(path: "api/v1/resumes", method: "POST", body: body, contentType: "multipart/form-data; boundary=\(boundary)")
    }

    func deleteResume(id: UUID) async throws {
        let (data, response) = try await authorizedRequest(path: "api/v1/resumes/\(id.uuidString)", method: "DELETE")
        try validate(response, data: data)
    }

    func updateResume(id: UUID, text: String) async throws -> Resume {
        let body = try JSONEncoder().encode(["text": text])
        return try await authenticated(
            path: "api/v1/resumes/\(id.uuidString)", method: "PATCH", body: body,
            contentType: "application/json"
        )
    }

    func startAnalysis(resumeID: UUID) async throws -> AnalysisJob {
        let body = try JSONEncoder().encode(AnalysisRequest(resume_id: resumeID.uuidString))
        return try await authenticated(
            path: "api/v1/resume-analysis", method: "POST", body: body,
            contentType: "application/json"
        )
    }

    func analysisJob(id: UUID) async throws -> AnalysisJob {
        try await authenticated(path: "api/v1/jobs/\(id.uuidString)")
    }

    func analysisHistory(resumeID: UUID, offset: Int) async throws -> [AnalysisJob] {
        let page: AnalysisJobPage = try await authenticated(path: "api/v1/jobs?resume_id=\(resumeID.uuidString)&limit=20&offset=\(offset)")
        return page.items
    }

    func startMatch(resumeID: UUID, description: String) async throws -> MatchJob {
        let body = try JSONEncoder().encode(MatchRequest(resume_id: resumeID.uuidString, job_description: description))
        return try await authenticated(path: "api/v1/job-matches", method: "POST", body: body, contentType: "application/json")
    }

    func matchJob(id: UUID) async throws -> MatchJob {
        try await authenticated(path: "api/v1/jobs/\(id.uuidString)")
    }

    func conversations(offset: Int) async throws -> ChatPage<ChatConversation> {
        try await authenticated(path: "api/v1/chat/conversations?limit=20&offset=\(offset)")
    }

    func createConversation(title: String) async throws -> ChatConversation {
        let body = try JSONEncoder().encode(["title": title])
        return try await authenticated(path: "api/v1/chat/conversations", method: "POST", body: body, contentType: "application/json")
    }

    func deleteConversation(id: UUID) async throws {
        let (data, response) = try await authorizedRequest(path: "api/v1/chat/conversations/\(id.uuidString)", method: "DELETE")
        try validate(response, data: data)
    }

    func chatMessages(conversationID: UUID, offset: Int) async throws -> ChatPage<ChatMessage> {
        try await authenticated(path: "api/v1/chat/conversations/\(conversationID.uuidString)/messages?limit=100&offset=\(offset)")
    }

    func saveChatMessage(conversationID: UUID, content: String) async throws -> ChatMessage {
        let body = try JSONEncoder().encode(["content": content])
        return try await authenticated(path: "api/v1/chat/conversations/\(conversationID.uuidString)/messages", method: "POST", body: body, contentType: "application/json")
    }

    func requestChatAnswer(conversationID: UUID, questionID: UUID) async throws -> ChatAnswerJob {
        struct Body: Encodable { let message_id: String; let allow_provider_fallbacks = true }
        let body = try JSONEncoder().encode(Body(message_id: questionID.uuidString))
        return try await authenticated(path: "api/v1/chat/conversations/\(conversationID.uuidString)/answers", method: "POST", body: body, contentType: "application/json")
    }

    func chatAnswerJob(conversationID: UUID, jobID: UUID) async throws -> ChatAnswerJob {
        try await authenticated(path: "api/v1/chat/conversations/\(conversationID.uuidString)/answers/\(jobID.uuidString)")
    }

    func retryChatAnswer(conversationID: UUID, jobID: UUID) async throws -> ChatAnswerJob {
        let body = Data("{\"allow_provider_fallbacks\":true}".utf8)
        return try await authenticated(path: "api/v1/chat/conversations/\(conversationID.uuidString)/answers/\(jobID.uuidString)/retry", method: "POST", body: body, contentType: "application/json")
    }

    func interviews(offset: Int) async throws -> ChatPage<InterviewSession> {
        try await authenticated(path: "api/v1/interviews/sessions?limit=20&offset=\(offset)")
    }

    func createInterview(resumeID: UUID, description: String) async throws -> InterviewSession {
        let body = try JSONEncoder().encode(["resume_id": resumeID.uuidString, "job_description": description])
        return try await authenticated(path: "api/v1/interviews/sessions", method: "POST", body: body, contentType: "application/json")
    }

    func deleteInterview(id: UUID) async throws {
        let (data, response) = try await authorizedRequest(path: "api/v1/interviews/sessions/\(id.uuidString)", method: "DELETE")
        try validate(response, data: data)
    }

    func interviewQuestions(sessionID: UUID) async throws -> ChatPage<InterviewQuestion> {
        try await authenticated(path: "api/v1/interviews/sessions/\(sessionID.uuidString)/questions?limit=100")
    }

    func saveInterviewAnswer(sessionID: UUID, questionID: UUID, answer: String) async throws -> InterviewQuestion {
        let body = try JSONEncoder().encode(["answer": answer])
        return try await authenticated(path: "api/v1/interviews/sessions/\(sessionID.uuidString)/questions/\(questionID.uuidString)/answer", method: "PUT", body: body, contentType: "application/json")
    }

    func requestInterviewJob(sessionID: UUID, questionID: UUID?) async throws -> InterviewJob {
        let path = questionID.map { "questions/\($0.uuidString)/feedback" } ?? "generation"
        let body = Data("{\"allow_provider_fallbacks\":true}".utf8)
        return try await authenticated(path: "api/v1/interviews/sessions/\(sessionID.uuidString)/\(path)", method: "POST", body: body, contentType: "application/json")
    }

    func interviewJob(sessionID: UUID, jobID: UUID) async throws -> InterviewJob {
        try await authenticated(path: "api/v1/interviews/sessions/\(sessionID.uuidString)/jobs/\(jobID.uuidString)")
    }

    func retryInterviewJob(sessionID: UUID, jobID: UUID) async throws -> InterviewJob {
        let body = Data("{\"allow_provider_fallbacks\":true}".utf8)
        return try await authenticated(path: "api/v1/interviews/sessions/\(sessionID.uuidString)/jobs/\(jobID.uuidString)/retry", method: "POST", body: body, contentType: "application/json")
    }

    func logout() async throws {
        try await sessions.signOut(baseURL: baseURL) { refreshToken in
            var request = URLRequest(url: endpoint("api/v1/auth/logout"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["refresh_token": refreshToken])
            let (data, response) = try await send(request)
            try validate(response, data: data)
        }
    }

    private func authenticated<T: Decodable>(path: String, method: String = "GET", body: Data? = nil, contentType: String? = nil) async throws -> T {
        let (data, response) = try await authorizedRequest(path: path, method: method, body: body, contentType: contentType)
        try validate(response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func authorizedRequest(path: String, method: String, body: Data? = nil, contentType: String? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let snapshot = try await sessions.snapshot(baseURL: baseURL) else { throw APIError.signedOut }
        func request(_ token: String) async throws -> (Data, HTTPURLResponse) {
            var request = URLRequest(url: endpoint(path))
            request.httpMethod = method
            request.httpBody = body
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
            return try await send(request)
        }
        let (data, response) = try await request(snapshot.tokens.accessToken)
        guard await sessions.isCurrent(snapshot) else { throw APIError.signedOut }
        guard response.statusCode == 401 else { return (data, response) }
        let updated = try await sessions.refreshed(snapshot, baseURL: baseURL) { refreshToken in
            try await post("api/v1/auth/refresh", body: ["refresh_token": refreshToken])
        }
        let retry = try await request(updated.tokens.accessToken)
        guard await sessions.isCurrent(updated) else { throw APIError.signedOut }
        return retry
    }

    private func endpoint(_ path: String) -> URL {
        let parts = path.split(separator: "?", maxSplits: 1)
        var components = URLComponents(url: baseURL.appending(path: String(parts[0])), resolvingAgainstBaseURL: false)!
        if parts.count == 2 { components.percentEncodedQuery = String(parts[1]) }
        return components.url!
    }

    private func post<T: Decodable>(_ path: String, body: [String: String]) async throws -> T {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await send(request)
        try validate(response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            return (data, response)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .dataNotAllowed:
                throw APIError.connectionUnavailable
            case .timedOut:
                throw APIError.connectionTimedOut
            default:
                throw error
            }
        }
    }

    private func validate(_ response: HTTPURLResponse, data: Data) throws {
        guard (200..<300).contains(response.statusCode) else {
            let message = try? JSONDecoder().decode(ErrorEnvelope.self, from: data).error.message
            throw APIError.server(response.statusCode, message)
        }
    }

    enum APIError: LocalizedError {
        case signedOut, invalidResponse, invalidBackendURL, fileTooLarge, connectionUnavailable, connectionTimedOut
        case server(Int, String?)
        var errorDescription: String? {
            switch self {
            case .signedOut: "Your session has ended. Please sign in."
            case .invalidResponse: "The server returned an invalid response."
            case .invalidBackendURL: "Enter a valid HTTPS backend URL, or use localhost for the simulator."
            case .fileTooLarge: "Choose a PDF smaller than 10 MB."
            case .connectionUnavailable: "Can’t reach the server. Check your connection or make sure the backend is running, then try again."
            case .connectionTimedOut: "The connection timed out. Check your connection and try again."
            case .server(let code, let message): message ?? "The server returned HTTP \(code)."
            }
        }
    }
}
