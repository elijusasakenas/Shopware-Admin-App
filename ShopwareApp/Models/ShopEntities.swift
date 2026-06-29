//
//  ShopEntities.swift
//  ShopwareApp
//
//  Smaller shop-management models surfaced in Shop settings and status:
//  sales channels, promotions, newsletter recipients, language stats,
//  log entries, and storefront domain health.
//

import SwiftUI

struct SalesChannel: Identifiable, Equatable {
    var id: String
    var name: String
    var maintenance: Bool = false
}

/// A language configured in the shop, used to read/write translatable fields
/// in that language via the Admin API's `sw-language-id` header.
struct ShopLanguage: Identifiable, Equatable, Hashable {
    var id: String
    var name: String
}

struct Promotion: Identifiable {
    var id: String
    var name: String
    var active: Bool
    var code: String?
}

struct NewsletterRecipient: Identifiable {
    var id: String
    var email: String
    var status: String
    var createdAt: Date?

    var statusLabel: String {
        switch status {
        case "optIn":  return "Confirmed"
        case "direct": return "Registered"
        case "optOut": return "Unsubscribed"
        default:       return "Pending"
        }
    }
}

struct LanguageStat: Identifiable {
    var id: String
    var name: String
    var count: Int
    var amount: Double
}

struct LogEntry: Identifiable {
    var id: String
    var message: String
    var level: Int
    var createdAt: Date?

    var levelLabel: String {
        switch level {
        case 500...: return "Critical"
        case 400...: return "Error"
        case 300...: return "Warning"
        case 250...: return "Notice"
        case 200...: return "Info"
        default:     return "Debug"
        }
    }

    var levelColor: Color {
        switch level {
        case 400...: return .red
        case 300...: return .amber
        default:     return .secondaryText
        }
    }
}

struct DomainStatus: Identifiable {
    var id: String { url }
    var url: String
    var statusCode: Int?
    var responseMs: Int?

    var isHealthy: Bool { (statusCode ?? 0) >= 200 && (statusCode ?? 0) < 400 }
}
