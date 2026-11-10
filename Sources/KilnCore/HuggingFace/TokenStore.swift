import Foundation
import Security

public protocol TokenStore: Sendable {
    func read() -> String?
    func save(_ token: String) throws
    func delete() throws
}

public struct KeychainError: Error, LocalizedError {
    public let status: OSStatus

    public var errorDescription: String? {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
        return "The Keychain could not be updated: \(detail)."
    }
}

/// Keeps the Hugging Face access token in the login Keychain.
public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    public init(service: String = "app.kiln.huggingface", account: String = "access-token") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ token: String) throws {
        let data = Data(token.utf8)
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
