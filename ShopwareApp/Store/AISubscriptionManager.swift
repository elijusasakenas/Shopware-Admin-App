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

    init() {
        updatesTask = Task { [weak self] in
            // Apply renewals, revocations, and Ask-to-Buy approvals as they land.
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlement()
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
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    latestTransactionJWS = verification.jwsRepresentation
                }
                await refreshEntitlement()
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
