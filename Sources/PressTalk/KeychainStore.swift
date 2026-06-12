import Foundation
import Security

/// Central identifiers for keychain and logging persistence.
/// Compile-time constants on purpose: `Bundle.main.bundleIdentifier` is nil
/// under `swift run` and unit tests, so it must never be used here (E7).
enum AppIdentity {
    static let keychainService = "com.kenny.presstalk"
    static let logSubsystem = "com.kenny.presstalk"
    /// Pre-rename identifiers (U11): drained by one-time migrations on
    /// first access, then removed.
    static let legacyKeychainService = "com.kenny.gcp-dictation-service"
    static let legacyBundleID = "com.kenny.gcp-dictation-service"
}

/// Secret storage abstraction so Configuration can be tested with an
/// in-memory store instead of the real keychain.
public protocol SecretStore {
    func string(forAccount account: String) -> String?
    @discardableResult func setString(_ value: String, forAccount account: String) -> Bool
    @discardableResult func removeString(forAccount account: String) -> Bool
}

/// Minimal wrapper around Security.framework generic passwords.
final class KeychainStore: SecretStore {
    private let service: String

    init(service: String = AppIdentity.keychainService) {
        self.service = service
    }

    func string(forAccount account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func setString(_ value: String, forAccount account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = data
            return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    @discardableResult
    func removeString(forAccount account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
