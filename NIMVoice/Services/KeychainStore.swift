import Foundation
import Security

/// Secure storage for the NVIDIA API key. The key is **never** written to
/// `UserDefaults` or hardcoded — only the iOS Keychain.
///
/// Items are stored with `kSecAttrSynchronizable = true`, which places them in
/// the **iCloud Keychain**. That gives us two things for free:
///   1. The key **survives app reinstalls** (a plain on-device keychain item is
///      not guaranteed to).
///   2. It syncs privately across the user's *own* Apple ID devices and is
///      readable only by this app — no one else can see it.
///
/// No iCloud capability/entitlement is required for synchronizable items; they
/// just need iCloud Keychain enabled on the device (on by default for most).
enum KeychainStore {
    private static let service = "com.nimvoice.apikey"
    private static let account = "NVIDIA_API_KEY"

    /// The identifying attributes shared by every query.
    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// Saves (or overwrites) the API key. Returns `true` on success.
    @discardableResult
    static func save(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return delete() }

        // Remove any existing copy (synced or local) — Keychain has no "upsert".
        var deleteQuery = baseQuery
        deleteQuery[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        SecItemDelete(deleteQuery as CFDictionary)

        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(trimmed.utf8)
        // Must be a non-"ThisDeviceOnly" accessibility to be synchronizable.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        attributes[kSecAttrSynchronizable as String] = kCFBooleanTrue
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    /// Reads the stored key, or `nil` if none. Matches both synced and any
    /// pre-existing local item (covers upgrades from an older build).
    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    @discardableResult
    static func delete() -> Bool {
        var query = baseQuery
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    static var hasKey: Bool {
        (read()?.isEmpty == false)
    }
}
