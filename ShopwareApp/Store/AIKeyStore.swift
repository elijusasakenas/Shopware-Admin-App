//
//  AIKeyStore.swift
//  ShopwareApp
//
//  Keychain-backed storage for a user-provided Anthropic, OpenAI, or Gemini
//  credential. Model calls go directly to the selected provider; Shopware MCP
//  calls still use the native-approval gateway.
//

import Combine
import Foundation
import Security

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case anthropic
    case openAI
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openAI: "OpenAI"
        case .gemini: "Gemini"
        }
    }

    static func detect(from key: String) -> AIProvider? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("sk-ant-") { return .anthropic }
        if trimmed.hasPrefix("AIza") { return .gemini }
        if trimmed.hasPrefix("sk-") { return .openAI }
        return nil
    }
}

enum AIProviderSelection: String, CaseIterable, Identifiable {
    case automatic
    case anthropic
    case openAI
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: AppLocalization.string("Automatic")
        case .anthropic: "Anthropic"
        case .openAI: "OpenAI"
        case .gemini: "Gemini"
        }
    }

    var provider: AIProvider? {
        switch self {
        case .automatic: nil
        case .anthropic: .anthropic
        case .openAI: .openAI
        case .gemini: .gemini
        }
    }

    init(provider: AIProvider) {
        switch provider {
        case .anthropic: self = .anthropic
        case .openAI: self = .openAI
        case .gemini: self = .gemini
        }
    }
}

struct AIProviderCredential: Codable, Equatable {
    let provider: AIProvider
    let key: String
}

/// The single source of truth for the assistant gate and request route.
/// A personal key is intentionally preferred when both options are available,
/// so subscribing never prevents a merchant from using their own billing.
enum AIAssistantAccessMode: Equatable {
    case unavailable
    case subscription
    case personalKey

    init(isSubscribed: Bool, hasPersonalKey: Bool) {
        if hasPersonalKey {
            self = .personalKey
        } else if isSubscribed {
            self = .subscription
        } else {
            self = .unavailable
        }
    }
}

@MainActor
final class AIKeyStore: ObservableObject {
    private let service = "com.opensource.shopwareapp.ai"
    private let credentialAccount = "ai-provider-credential-v1"
    private let legacyAnthropicAccount = "anthropic-api-key"

    /// Whether a key is stored, for view routing (the key itself is only
    /// read on demand when a request is made).
    @Published private(set) var hasKey = false
    @Published private(set) var provider: AIProvider?

    init() {
        let credential = read()
        hasKey = credential != nil
        provider = credential?.provider
    }

    func read() -> AIProviderCredential? {
        if let data = readData(account: credentialAccount),
           let credential = try? JSONDecoder().decode(AIProviderCredential.self, from: data),
           !credential.key.isEmpty {
            return credential
        }

        // Credentials saved by releases before multi-provider support were
        // plain Anthropic keys. Keep them working without asking the user to
        // paste the secret again.
        guard let data = readData(account: legacyAnthropicAccount),
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return AIProviderCredential(provider: .anthropic, key: key)
    }

    func save(_ key: String, provider selectedProvider: AIProvider? = nil) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ShopwareAPIError.message("The API key is empty.")
        }
        guard let resolvedProvider = selectedProvider ?? AIProvider.detect(from: trimmed) else {
            throw ShopwareAPIError.message("The API key provider could not be detected. Choose Anthropic, OpenAI, or Gemini manually.")
        }
        let credential = AIProviderCredential(provider: resolvedProvider, key: trimmed)
        guard let encoded = try? JSONEncoder().encode(credential) else {
            throw ShopwareAPIError.message("Could not prepare the API key for secure storage.")
        }
        let values: [String: Any] = [
            kSecValueData as String: encoded,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let query = baseQuery(account: credentialAccount)
        let updateStatus = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        let status: OSStatus
        if updateStatus == errSecItemNotFound {
            status = SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil)
        } else {
            status = updateStatus
        }
        guard status == errSecSuccess else {
            throw ShopwareAPIError.message("Could not save the API key to Keychain.")
        }
        _ = SecItemDelete(baseQuery(account: legacyAnthropicAccount) as CFDictionary)
        hasKey = true
        provider = resolvedProvider
    }

    func clear() throws {
        let statuses = [credentialAccount, legacyAnthropicAccount].map {
            SecItemDelete(baseQuery(account: $0) as CFDictionary)
        }
        guard statuses.allSatisfy({ $0 == errSecSuccess || $0 == errSecItemNotFound }) else {
            throw ShopwareAPIError.message("Could not remove the API key from Keychain.")
        }
        hasKey = false
        provider = nil
    }

    private func readData(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
