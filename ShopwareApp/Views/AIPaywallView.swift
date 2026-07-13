//
//  AIPaywallView.swift
//  ShopwareApp
//
//  Subscription gate for the AI assistant: pitch, price, purchase, restore.
//

import StoreKit
import SwiftUI

struct AIPaywallView: View {
    @ObservedObject var subscriptions: AISubscriptionManager
    @ObservedObject var aiKey: AIKeyStore
    @State private var keyDraft = ""
    @State private var keyError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                VStack(alignment: .leading, spacing: 14) {
                    feature(icon: "chart.bar.xaxis", title: "Ask about your numbers",
                            detail: "Today's revenue, open orders, low stock, top products — just ask.")
                    feature(icon: "shippingbox", title: "Manage products by chatting",
                            detail: "\"Set the stock of the blue hoodie to 50\" — done.")
                    feature(icon: "tag", title: "Promotions and orders",
                            detail: "Activate promotions, ship orders, mark payments as paid.")
                    feature(icon: "checkmark.shield", title: "You stay in control",
                            detail: "Every change to your shop needs your approval before it runs.")
                }

                if let message = subscriptions.errorMessage {
                    ErrorBanner(message: message)
                }

                if subscriptions.hasLoadedEntitlements && subscriptions.product == nil {
                    // No product means StoreKit has nothing to sell: in the
                    // simulator the scheme's StoreKit configuration is missing;
                    // in production the App Store Connect product is absent.
                    ErrorBanner(message: String(localized: "The subscription is currently unavailable. Please try again later."))
                }

                VStack(spacing: 12) {
                    Button {
                        Task { await subscriptions.purchase() }
                    } label: {
                        if subscriptions.isPurchasing {
                            ProgressView().tint(Color.inverseText)
                        } else {
                            Text("Subscribe for \(priceText)")
                                .font(.headline)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(subscriptions.product == nil || subscriptions.isPurchasing)
                    .opacity(subscriptions.product == nil ? 0.5 : 1)

                    Button {
                        Task { await subscriptions.restorePurchases() }
                    } label: {
                        Text("Restore purchases")
                            .font(.subheadline)
                            .foregroundStyle(Color.shopwareBlue)
                    }

                    Text("Auto-renews monthly. Cancel anytime in your App Store settings.")
                        .font(.caption)
                        .foregroundStyle(Color.secondaryText)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)

                    // Required for auto-renewable subscriptions (guideline 3.1.2).
                    HStack(spacing: 16) {
                        Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        Link("Privacy Policy", destination: URL(string: "https://asakenas.com/shopware-admin-app/privacy/")!)
                    }
                    .font(.caption)
                    .foregroundStyle(Color.shopwareBlue)
                    .frame(maxWidth: .infinity)
                }

                ownKeySection
            }
            .padding(20)
        }
        .background(Color.appBackground)
        .task { await subscriptions.refresh() }
    }

    /// Alternative to the subscription: the user brings their own Anthropic
    /// API key and pays Anthropic directly for what they use.
    private var ownKeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Rectangle().fill(Color.border).frame(height: 1)
                Text("or")
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText)
                Rectangle().fill(Color.border).frame(height: 1)
            }

            Text("Use your own API key")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.primaryText)
            Text("Have an Anthropic API key? Use the assistant without a subscription. The key is stored in your device's keychain and requests go directly to Anthropic — you pay Anthropic for what you use.")
                .font(.footnote)
                .foregroundStyle(Color.secondaryText)

            if let keyError {
                ErrorBanner(message: keyError)
            }

            SecureField("sk-ant-...", text: $keyDraft)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.border, lineWidth: 1)
                )

            Button {
                do {
                    try aiKey.save(keyDraft)
                    keyDraft = ""
                    keyError = nil
                } catch {
                    keyError = error.shopwareDisplayMessage
                }
            } label: {
                Text("Use my key")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(Color.primaryText)
                    .background(Color.controlBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var priceText: String {
        if let product = subscriptions.product {
            return String(localized: "\(product.displayPrice) / month")
        }
        return String(localized: "4 € / month")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(Color.shopwareBlue)
            Text("AI Shop Assistant")
                .font(.title.weight(.bold))
                .foregroundStyle(Color.primaryText)
            Text("Run your Shopware store by chatting. The assistant reads your data and makes changes for you — with your approval.")
                .font(.subheadline)
                .foregroundStyle(Color.secondaryText)
        }
    }

    private func feature(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.shopwareBlue)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.primaryText)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Color.secondaryText)
            }
        }
    }
}
