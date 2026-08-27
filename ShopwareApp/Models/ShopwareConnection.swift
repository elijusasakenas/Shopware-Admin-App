//
//  ShopwareConnection.swift
//  ShopwareApp
//
//  A saved Shopware shop: stable identity, credentials, an optional
//  user-given label, and URL normalization.
//

import Foundation

struct ShopwareConnection: Codable, Identifiable, Equatable, Sendable {
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
    var displayHost: String {
        Self.normalizedURL(from: shopURL)?.host ?? shopURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What to show in the UI: the user's label if set, otherwise the host.
    var displayName: String {
        if let label = label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return label
        }
        return displayHost
    }

    /// Shop origin used for Admin API calls. Throws instead of inventing a URL.
    func resolvedBaseURL() throws -> URL {
        guard let url = Self.normalizedURL(from: shopURL) else {
            throw ShopwareAPIError.message(
                AppLocalization.string("Enter a valid shop URL, like https://your-shop.com.")
            )
        }
        return url
    }

    /// Parses a merchant-entered shop URL into an http(s) origin.
    /// Returns nil for empty, non-http(s), or unparseable values.
    static func normalizedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withScheme: String
        if let separator = trimmed.range(of: "://") {
            let scheme = trimmed[..<separator.lowerBound].lowercased()
            guard scheme == "http" || scheme == "https" else { return nil }
            withScheme = trimmed
        } else {
            withScheme = "https://\(trimmed)"
        }

        guard var components = URLComponents(string: withScheme) else { return nil }
        components.user = nil
        components.password = nil
        components.fragment = nil
        guard let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty
        else { return nil }
        components.scheme = scheme
        components.host = host
        if components.path == "/" {
            components.path = ""
        } else if components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        return components.url
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
