import Foundation
import Security

/// App passwords live only in the macOS keychain — never in UserDefaults or the
/// accounts file. One generic-password item per account, keyed by account id.
public enum CredentialStore {
    static let service = "com.ebb.app"

    public static func password(for accountID: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data,
            let value = String(data: data, encoding: .utf8), !value.isEmpty
        else { return nil }
        return value
    }

    /// Google shows app passwords in groups of four ("abcd efgh ijkl mnop");
    /// the spaces are not part of it, so they are stripped before saving.
    public static func normalize(_ password: String) -> String {
        password.filter { !$0.isWhitespace }
    }

    public static func setPassword(_ password: String, for accountID: UUID) throws {
        let value = normalize(password)
        guard !value.isEmpty else {
            removePassword(for: accountID)
            return
        }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
        ]
        let data = Data(value.utf8)
        var status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            add[kSecAttrLabel as String] = "Ebb app password"
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    public static func removePassword(for accountID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
