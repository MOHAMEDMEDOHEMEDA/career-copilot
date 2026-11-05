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
