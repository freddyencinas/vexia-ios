import Foundation
import Security

/// Abstraction over secure storage.
protocol SecureStore: Sendable {
    func string(for key: String) -> String?
    func set(_ value: String?, for key: String)
}

/// Keychain-backed implementation. Uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
nonisolated struct KeychainStore: SecureStore {
    let service: String

    init(service: String = "com.vexia.finance.ios") { self.service = service }

    nonisolated func string(for key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    nonisolated func set(_ value: String?, for key: String) {
        let query = baseQuery(key)
        SecItemDelete(query as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private nonisolated func baseQuery(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }
}

/// In-memory store for tests and previews.
nonisolated final class InMemorySecureStore: SecureStore, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()
    nonisolated init() {}
    nonisolated func string(for key: String) -> String? { lock.withLock { storage[key] } }
    nonisolated func set(_ value: String?, for key: String) { lock.withLock { storage[key] = value } }
}
