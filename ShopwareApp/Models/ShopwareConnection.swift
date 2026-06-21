//
//  ShopwareConnection.swift
//  ShopwareApp
//
//  A saved Shopware shop: stable identity, credentials, an optional
//  user-given label, and URL normalization.
//

import Foundation

struct ShopwareConnection: Codable, Identifiable, Equatable {
    var id: UUID
    var shopURL: String
    var accessKey: String
    var secretKey: String
    /// Optional name the user gave this shop. Falls back to the host.
    var label: String?

    init(id: UUID = UUID(), shopURL: String, accessKey: String, secretKey: String, label: String? = nil) {
        self.id = id
        self.shopURL = shopURL
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.label = label
    }

    /// Host derived from the shop URL, e.g. "shop.example.com".
    var displayHost: String { normalizedBaseURL.host ?? shopURL }

    /// What to show in the UI: the user's label if set, otherwise the host.
    var displayName: String {
        if let label = label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return label
        }
        return displayHost
    }

    var normalizedBaseURL: URL {
        let trimmed = shopURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let withScheme = trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://")
            ? trimmed : "https://\(trimmed)"
        return URL(string: withScheme.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) ?? URL(string: "https://example.com")!
    }

    // Tolerant decoding: connections saved before multi-shop support have no
    // `id` or `label`, so synthesize a stable id and leave the label empty.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        shopURL = try container.decode(String.self, forKey: .shopURL)
        accessKey = try container.decode(String.self, forKey: .accessKey)
        secretKey = try container.decode(String.self, forKey: .secretKey)
        label = try container.decodeIfPresent(String.self, forKey: .label)
    }
}
