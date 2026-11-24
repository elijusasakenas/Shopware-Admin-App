//
//  ShopwareAdminClient+Settings.swift
//  ShopwareApp
//
//  Shop settings: promotions, newsletter, maintenance, logs, and status info.
//

import Foundation

extension ShopwareAdminClient {
    func fetchPromotions() async throws -> [Promotion] {
        let response = try await requestJSON(path: "/api/search/promotion", method: "POST", body: [
            "limit": 100,
            "sort": [["field": "createdAt", "order": "DESC"]]
        ])
        return (response["data"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            let attrs = entityAttributes(of: row)
            return Promotion(
                id: id,
                name: translatedName(from: attrs) ?? attrs["name"] as? String ?? "Unnamed promotion",
                active: attrs["active"] as? Bool ?? false,
                code: attrs["code"] as? String
            )
        }
    }

    func setPromotionActive(promotionID: String, active: Bool) async throws {
        _ = try await requestJSON(path: "/api/promotion/\(promotionID)", method: "PATCH", body: [
            "active": active
        ])
    }

    /// All payment methods with the sales channels that offer them, in the
    /// order customers see them at checkout.
    func fetchPaymentMethods() async throws -> [PaymentMethod] {
        let response = try await requestJSON(path: "/api/search/payment-method", method: "POST", body: [
            "limit": 100,
            "sort": [["field": "position", "order": "ASC"], ["field": "name", "order": "ASC"]],
            "associations": ["salesChannels": [:]]
        ])
        return (response["data"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            let attrs = entityAttributes(of: row)
            let translated = attrs["translated"] as? [String: Any]
            let description = (translated?["description"] as? String ?? attrs["description"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return PaymentMethod(
                id: id,
                name: translatedName(from: attrs) ?? attrs["name"] as? String
                    ?? AppLocalization.string("Unnamed payment method"),
                description: description?.isEmpty == false ? description : nil,
                active: attrs["active"] as? Bool ?? false,
                position: attrs["position"] as? Int ?? 0,
                flow: paymentFlow(from: attrs),
                salesChannelIDs: relationshipIDs(from: (row["relationships"] as? [String: Any])?["salesChannels"])
                    ?? (attrs["salesChannels"] as? [[String: Any]])?.compactMap { $0["id"] as? String }
                    ?? []
            )
        }
    }

    /// Whether the Shopware Payments extension is installed and active.
    ///
    /// Shopware ships it as an app on 6.5.7–6.6 and as a Shopware Service
    /// (also installed as an app) on 6.7.1+. Its technical name is not
    /// documented, so both the `app` and `plugin` entities are searched and
    /// an active entry matches when its technical name or label reads
    /// "Shopware Payments" (ignoring case, spaces, dashes and underscores).
    func isShopwarePaymentsActive() async throws -> Bool {
        let body: [String: Any] = [
            "limit": 100,
            "filter": [["type": "equals", "field": "active", "value": true]]
        ]
        async let apps = requestJSON(path: "/api/search/app", method: "POST", body: body)
        async let plugins = requestJSON(path: "/api/search/plugin", method: "POST", body: body)
        // Either list may be forbidden for the integration; one readable list is enough.
        let rows = ((try? await apps)?["data"] as? [[String: Any]] ?? [])
            + ((try? await plugins)?["data"] as? [[String: Any]] ?? [])
        return rows.contains { row in
            let attrs = entityAttributes(of: row)
            guard attrs["active"] as? Bool ?? true else { return false }
            let candidates = [
                attrs["name"] as? String,
                attrs["label"] as? String,
                (attrs["translated"] as? [String: Any])?["label"] as? String
            ]
            return candidates.contains { Self.isShopwarePaymentsName($0) }
        }
    }

    static func isShopwarePaymentsName(_ value: String?) -> Bool {
        guard let value else { return false }
        let normalized = value.lowercased().filter { $0.isLetter || $0.isNumber }
        return normalized.contains("shopwarepayments")
    }

    func setPaymentMethodActive(paymentMethodID: String, active: Bool) async throws {
        _ = try await requestJSON(path: "/api/payment-method/\(paymentMethodID)", method: "PATCH", body: [
            "active": active
        ])
    }

    /// Shopware adds runtime `synchronous` / `asynchronous` flags derived from
    /// the payment handler. Older or customized shops may omit them.
    private func paymentFlow(from attrs: [String: Any]) -> PaymentMethod.Flow {
        if attrs["asynchronous"] as? Bool == true { return .redirect }
        if attrs["synchronous"] as? Bool == true { return .direct }
        return .unknown
    }

    private func relationshipIDs(from relationship: Any?) -> [String]? {
        guard let rel = relationship as? [String: Any], let data = rel["data"] as? [[String: Any]] else { return nil }
        return data.compactMap { $0["id"] as? String }
    }

    func countRecentCustomers(since: Date) async throws -> Int {
        try await countEntity("customer", filters: [[
            "type": "range",
            "field": "createdAt",
            "parameters": ["gte": since.iso8601String]
        ]])
    }

    func fetchRecentCustomers(since: Date? = nil) async throws -> [CustomerRegistration] {
        var body: [String: Any] = [
            "limit": since == nil ? 25 : 100,
            "sort": [["field": "createdAt", "order": "DESC"]]
        ]
        if let since {
            body["filter"] = [[
                "type": "range",
                "field": "createdAt",
                "parameters": ["gte": since.iso8601String]
            ]]
        }
        let response = try await requestJSON(path: "/api/search/customer", method: "POST", body: body)
        return (response["data"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            let attrs = entityAttributes(of: row)
            let first = attrs["firstName"] as? String ?? ""
            let last = attrs["lastName"] as? String ?? ""
            return CustomerRegistration(
                id: id,
                name: "\(first) \(last)".trimmingCharacters(in: .whitespaces),
                email: attrs["email"] as? String ?? "Unknown",
                createdAt: date(from: attrs["createdAt"] as? String),
                guest: attrs["guest"] as? Bool ?? false
            )
        }
    }

    func fetchLogEntries() async throws -> [LogEntry] {
        let response = try await requestJSON(path: "/api/search/log-entry", method: "POST", body: [
            "limit": 25,
            "sort": [["field": "createdAt", "order": "DESC"]]
        ])
        return (response["data"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            let attrs = entityAttributes(of: row)
            return LogEntry(
                id: id,
                message: attrs["message"] as? String ?? "No message",
                level: attrs["level"] as? Int ?? 200,
                createdAt: date(from: attrs["createdAt"] as? String)
            )
        }
    }

    func fetchDomainURLs() async throws -> [String] {
        let response = try await requestJSON(path: "/api/search/sales-channel-domain", method: "POST", body: [
            "limit": 10
        ])
        return (response["data"] as? [[String: Any]] ?? []).compactMap { row in
            entityAttributes(of: row)["url"] as? String
        }
    }

    func fetchShopwareVersion() async throws -> String {
        let response = try await requestJSON(path: "/api/_info/version", method: "GET")
        return response["version"] as? String ?? "Unknown"
    }

    func fetchNewsletterRecipients() async throws -> [NewsletterRecipient] {
        let response = try await requestJSON(path: "/api/search/newsletter-recipient", method: "POST", body: [
            "limit": 100,
            "sort": [["field": "createdAt", "order": "DESC"]]
        ])
        return (response["data"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            let attrs = entityAttributes(of: row)
            return NewsletterRecipient(
                id: id,
                email: attrs["email"] as? String ?? "Unknown",
                status: attrs["status"] as? String ?? "notSet",
                createdAt: date(from: attrs["createdAt"] as? String)
            )
        }
    }

    func setMaintenance(salesChannelID: String, enabled: Bool) async throws {
        _ = try await requestJSON(path: "/api/sales-channel/\(salesChannelID)", method: "PATCH", body: [
            "maintenance": enabled
        ])
    }
}
