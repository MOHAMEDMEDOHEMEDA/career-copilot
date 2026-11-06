import Foundation
import Security

struct TokenPair: Codable {
    let accessToken: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

enum TokenStore {
    private struct StoredTokens: Codable {
        let baseURL: String
        let tokens: TokenPair
    }
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.careercopilot.spike",
        kSecAttrAccount as String: "tokens"
    ]

    static func save(_ tokens: TokenPair, baseURL: URL) throws {
        let data = try JSONEncoder().encode(StoredTokens(baseURL: baseURL.absoluteString, tokens: tokens))
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw StoreError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw StoreError.keychain(status)
        }
    }

    static func load(baseURL: URL) throws -> TokenPair? {
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(search as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw StoreError.keychain(status) }
        let stored = try JSONDecoder().decode(StoredTokens.self, from: data)
        guard stored.baseURL == baseURL.absoluteString else { return nil }
        return stored.tokens
    }

    static func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError.keychain(status) }
    }

    enum StoreError: LocalizedError {
        case keychain(OSStatus)
        var errorDescription: String? {
            switch self {
            case .keychain(let status):
                "Unable to access the Keychain (status \(status))."
            }
        }
    }
}

protocol SessionTokenStoring {
    func load(baseURL: URL) throws -> TokenPair?
    func save(_ tokens: TokenPair, baseURL: URL) throws
    func clear() throws
}

struct KeychainSessionTokenStore: SessionTokenStoring {
    func load(baseURL: URL) throws -> TokenPair? { try TokenStore.load(baseURL: baseURL) }
    func save(_ tokens: TokenPair, baseURL: URL) throws { try TokenStore.save(tokens, baseURL: baseURL) }
    func clear() throws { try TokenStore.clear() }
}

struct SessionSnapshot {
    let generation: UUID
    let tokens: TokenPair
}

actor SessionCoordinator {
    static let shared = SessionCoordinator()

    private let store: any SessionTokenStoring
    private var generation = UUID()
    private var isSigningOut = false
    private var refreshTask: (id: UUID, task: Task<TokenPair, Error>)?

    init(store: any SessionTokenStoring = KeychainSessionTokenStore()) {
        self.store = store
    }

    func startSession(_ tokens: TokenPair, baseURL: URL) throws {
        guard !isSigningOut else { throw APIClient.APIError.signedOut }
        try store.save(tokens, baseURL: baseURL)
        generation = UUID()
        refreshTask = nil
    }

    func snapshot(baseURL: URL) throws -> SessionSnapshot? {
        guard !isSigningOut, let tokens = try store.load(baseURL: baseURL) else { return nil }
        return SessionSnapshot(generation: generation, tokens: tokens)
    }

    func isCurrent(_ snapshot: SessionSnapshot) -> Bool {
        !isSigningOut && snapshot.generation == generation
    }

    func refreshed(
        _ snapshot: SessionSnapshot,
        baseURL: URL,
        operation: @escaping (String) async throws -> TokenPair
    ) async throws -> SessionSnapshot {
        guard isCurrent(snapshot), let current = try store.load(baseURL: baseURL) else {
            throw APIClient.APIError.signedOut
        }
        if current.refreshToken != snapshot.tokens.refreshToken {
            return SessionSnapshot(generation: generation, tokens: current)
        }
        let pending: (id: UUID, task: Task<TokenPair, Error>)
        if let refreshTask {
            pending = refreshTask
        } else {
            pending = (UUID(), Task { try await operation(snapshot.tokens.refreshToken) })
            refreshTask = pending
        }
        do {
            let updated = try await pending.task.value
            guard isCurrent(snapshot), let stored = try store.load(baseURL: baseURL) else {
                throw APIClient.APIError.signedOut
            }
            if stored.refreshToken == snapshot.tokens.refreshToken {
                try store.save(updated, baseURL: baseURL)
            }
            if refreshTask?.id == pending.id { refreshTask = nil }
            return SessionSnapshot(generation: generation, tokens: try store.load(baseURL: baseURL) ?? updated)
        } catch {
            if refreshTask?.id == pending.id && !isSigningOut { refreshTask = nil }
            throw error
        }
    }

    func signOut(baseURL: URL, revoke: @escaping (String) async throws -> Void) async throws {
        guard !isSigningOut else { throw APIClient.APIError.signedOut }
        guard var tokens = try store.load(baseURL: baseURL) else { return }
        isSigningOut = true
        generation = UUID()
        defer { isSigningOut = false }
        if let pending = refreshTask {
            do {
                tokens = try await pending.task.value
                try store.save(tokens, baseURL: baseURL)
                if refreshTask?.id == pending.id { refreshTask = nil }
            } catch {
                if refreshTask?.id == pending.id { refreshTask = nil }
                throw error
            }
        }
        try await revoke(tokens.refreshToken)
        try store.clear()
    }
}
