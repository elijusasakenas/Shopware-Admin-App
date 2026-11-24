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

struct Promotion: Identifiable {
    var id: String
    var name: String
    var active: Bool
    var code: String?
}

/// A shop payment method. Shopware runs each method through a payment
/// handler: synchronous handlers settle in the checkout, asynchronous ones
/// redirect the customer to the payment provider and come back afterwards.
struct PaymentMethod: Identifiable, Equatable {
    enum Flow: Equatable {
        /// Settled during checkout (invoice, prepayment, cash on delivery…).
        case direct
        /// Customer is redirected to the provider (PayPal, card gateways…).
        case redirect
        /// Shopware did not report the handler type.
        case unknown
    }

    var id: String
    var name: String
    var description: String?
    var active: Bool
    var position: Int
    var flow: Flow
    /// Sales channels that offer this method at checkout.
    var salesChannelIDs: [String]
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
