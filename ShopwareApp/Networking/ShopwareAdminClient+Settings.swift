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

    func fetchRecentCustomers() async throws -> [CustomerRegistration] {
        let response = try await requestJSON(path: "/api/search/customer", method: "POST", body: [
            "limit": 25,
            "sort": [["field": "createdAt", "order": "DESC"]]
        ])
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
