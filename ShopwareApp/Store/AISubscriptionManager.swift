//
//  AISubscriptionManager.swift
//  ShopwareApp
//
//  StoreKit 2 wrapper for the AI assistant's monthly subscription. Tracks the
//  entitlement, drives purchase/restore, and hands the signed transaction to
//  the AI proxy so it can verify the subscription server-side.
//

import Combine
import Foundation
import StoreKit

@MainActor
final class AISubscriptionManager: ObservableObject {
    /// Shared instance so only one `Transaction.updates` listener is registered
    /// across chat and settings.
    static let shared = AISubscriptionManager()

    /// Auto-renewable subscription; create the same product in App Store
    /// Connect. The local StoreKit configuration (ShopwareApp/Configuration/
    /// ShopwareAI.storekit, selected in the scheme's Run options) provides it
    /// for simulator testing.
    static let productID = "com.asakenas.shopwareapp.ai.monthly"

    @Published private(set) var isSubscribed = false
    @Published private(set) var product: Product?
    @Published private(set) var hasLoadedEntitlements = false
    @Published private(set) var isPurchasing = false
    @Published var errorMessage: String?

    /// The most recent verified transaction, as the signed JWS the AI proxy
    /// validates against Apple's certificate chain.
    private var latestTransactionJWS: String?
    private var updatesTask: Task<Void, Never>?
    /// Avoids calling `finish()` more than once when purchase success and
    /// `Transaction.updates` both deliver the same transaction.
    private var finishedTransactionIDs = Set<UInt64>()

    private init() {
        updatesTask = Task { [weak self] in
            // Apply renewals, revocations, and Ask-to-Buy approvals as they land.
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task { await refresh() }
    }

    deinit { updatesTask?.cancel() }

    func refresh() async {
        if product == nil {
            product = try? await Product.products(for: [Self.productID]).first
        }
        await refreshEntitlement()
    }

    func purchase() async {
        guard let product, !isPurchasing else { return }
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                await handle(verification)
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        errorMessage = nil
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    /// The signed transaction the proxy needs to authorize a chat request.
    func entitlementJWS() async -> String? {
        if latestTransactionJWS == nil { await refreshEntitlement() }
        return latestTransactionJWS
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        if case .verified(let transaction) = result, transaction.productID == Self.productID {
            await finishIfNeeded(transaction)
        }
        // Always re-read entitlements: revocations and unverified updates
        // must still clear a stale subscription.
        await refreshEntitlement()
    }

    private func finishIfNeeded(_ transaction: Transaction) async {
        guard finishedTransactionIDs.insert(transaction.id).inserted else { return }
        await transaction.finish()
    }

    private func refreshEntitlement() async {
        var subscribed = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.productID,
                  transaction.revocationDate == nil else { continue }
            subscribed = true
            latestTransactionJWS = result.jwsRepresentation
        }
        isSubscribed = subscribed
        if !subscribed { latestTransactionJWS = nil }
        hasLoadedEntitlements = true
    }
}
