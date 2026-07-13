//
//  AIKeyStore.swift
//  ShopwareApp
//
//  Keychain-backed storage for the user's own Anthropic API key. When a key
//  is saved, the AI assistant talks to the Anthropic API directly from the
//  device (no subscription, no proxy) — the user pays Anthropic themselves.
//

import Combine
import Foundation
import Security

@MainActor
final class AIKeyStore: ObservableObject {
    private let service = "com.opensource.shopwareapp.ai"
    private let account = "anthropic-api-key"

    /// Whether a key is stored, for view routing (the key itself is only
    /// read on demand when a request is made).
    @Published private(set) var hasKey = false

    init() {
        hasKey = read() != nil
    }

    func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            return nil
        }
        return key
    }

    func save(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ShopwareAPIError.message("The API key is empty.")
        }
        try? clear()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(trimmed.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
            throw ShopwareAPIError.message("Could not save the API key to Keychain.")
        }
        hasKey = true
    }

    func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        let acceptable: [OSStatus] = [errSecSuccess, errSecItemNotFound, errSecMissingEntitlement]
        guard acceptable.contains(status) else {
            throw ShopwareAPIError.message("Could not remove the API key from Keychain.")
        }
        hasKey = false
    }
}
