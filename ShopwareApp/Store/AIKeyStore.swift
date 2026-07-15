//
//  AIKeyStore.swift
//  ShopwareApp
//
//  Keychain-backed storage for the user's own Anthropic API key. Model calls
//  go directly to Anthropic; MCP calls still use the native-approval gateway.
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
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
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
        let values: [String: Any] = [
            kSecValueData as String: Data(trimmed.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, values as CFDictionary)
        let status: OSStatus
        if updateStatus == errSecItemNotFound {
            status = SecItemAdd(baseQuery.merging(values) { _, new in new } as CFDictionary, nil)
        } else {
            status = updateStatus
        }
        guard status == errSecSuccess else {
            throw ShopwareAPIError.message("Could not save the API key to Keychain.")
        }
        hasKey = true
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ShopwareAPIError.message("Could not remove the API key from Keychain.")
        }
        hasKey = false
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
