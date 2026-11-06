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
            throw URLError(.badURL)
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
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        return (data, response)
    }

    private func validate(_ response: HTTPURLResponse, data: Data) throws {
        guard (200..<300).contains(response.statusCode) else {
            let message = try? JSONDecoder().decode(ErrorEnvelope.self, from: data).error.message
            throw APIError.server(response.statusCode, message)
        }
    }

    enum APIError: LocalizedError {
        case signedOut, invalidResponse, fileTooLarge
        case server(Int, String?)
        var errorDescription: String? {
            switch self {
            case .signedOut: "Your session has ended. Please sign in."
            case .invalidResponse: "The server returned an invalid response."
            case .fileTooLarge: "Choose a PDF smaller than 10 MB."
            case .server(let code, let message): message ?? "The server returned HTTP \(code)."
            }
        }
    }
}
