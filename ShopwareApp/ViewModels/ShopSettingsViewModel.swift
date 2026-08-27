//
//  ShopSettingsViewModel.swift
//  ShopwareApp
//
//  Shop settings / status / registrations reads and promotion toggles.
//  Sales-channel maintenance stays on the session dashboard VM because it
//  owns the live `salesChannels` list used by the dashboard selector.
//

import Combine
import Foundation

@MainActor
final class ShopSettingsViewModel: ObservableObject {
    private let client: ShopwareAdminClient

    init(client: ShopwareAdminClient) {
        self.client = client
    }

    func promotions() async throws -> [Promotion] {
        try await client.fetchPromotions()
    }

    func setPromotionActive(promotionID: String, active: Bool) async throws {
        try await client.setPromotionActive(promotionID: promotionID, active: active)
    }

    func newsletterRecipients() async throws -> [NewsletterRecipient] {
        try await client.fetchNewsletterRecipients()
    }

    func recentCustomers(since: Date? = nil) async throws -> [CustomerRegistration] {
        try await client.fetchRecentCustomers(since: since)
    }

    func recentCustomerCount(since: Date) async throws -> Int {
        try await client.countRecentCustomers(since: since)
    }

    func logEntries() async throws -> [LogEntry] {
        try await client.fetchLogEntries()
    }

    func domainURLs() async throws -> [String] {
        try await client.fetchDomainURLs()
    }

    func shopwareVersion() async throws -> String {
        try await client.fetchShopwareVersion()
    }
}
