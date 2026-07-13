//
//  AIAssistantSettingsCard.swift
//  ShopwareApp
//
//  Settings card for the AI assistant: subscription status + Apple's
//  manage-subscription sheet, bring-your-own-key management, and the
//  device-local usage counters for the current month.
//

import StoreKit
import SwiftUI

struct AIAssistantSettingsCard: View {
    @StateObject private var subscriptions = AISubscriptionManager()
    @StateObject private var aiKey = AIKeyStore()
    @State private var usage = AIUsage.snapshot()
    @State private var showManageSubscriptions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Assistant")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.primaryText)

            statusRow(
                title: "Subscription",
                value: subscriptions.isSubscribed
                    ? String(localized: "Active")
                    : String(localized: "Not subscribed"),
                active: subscriptions.isSubscribed
            )
            statusRow(
                title: "Own API key",
                value: aiKey.hasKey
                    ? String(localized: "Saved in Keychain")
                    : String(localized: "Not set"),
                active: aiKey.hasKey
            )

            Divider()

            Text("Usage this month")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.primaryText)
            usageRow(label: String(localized: "Requests"), value: usage.requests)
            usageRow(label: String(localized: "Input tokens"), value: usage.inputTokens)
            usageRow(label: String(localized: "Output tokens"), value: usage.outputTokens)
            Text("Counted on this device; resets monthly. With your own API key, billing lives in your Anthropic console.")
                .font(.caption)
                .foregroundStyle(Color.secondaryText)

            Divider()

            manageSubscriptionButton
            Button {
                Task { await subscriptions.restorePurchases() }
            } label: {
                Text("Restore purchases")
                    .font(.subheadline)
                    .foregroundStyle(Color.shopwareBlue)
            }
            if aiKey.hasKey {
                Button(role: .destructive) {
                    try? aiKey.clear()
                } label: {
                    Text("Remove API key")
                        .font(.subheadline)
                        .foregroundStyle(Color.red)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.border, lineWidth: 1))
        .onAppear { usage = AIUsage.snapshot() }
    }

    /// Apple's native management sheet on iOS; the account subscriptions page
    /// elsewhere (the sheet API doesn't exist on macOS).
    @ViewBuilder
    private var manageSubscriptionButton: some View {
        #if os(iOS)
        Button {
            showManageSubscriptions = true
        } label: {
            Text("Manage subscription")
                .font(.subheadline)
                .foregroundStyle(Color.shopwareBlue)
        }
        .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
        #else
        Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
            Text("Manage subscription")
                .font(.subheadline)
                .foregroundStyle(Color.shopwareBlue)
        }
        #endif
    }

    private func statusRow(title: LocalizedStringKey, value: String, active: Bool) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.primaryText)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(active ? Color.green : Color.secondaryText.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryText)
            }
        }
    }

    private func usageRow(label: String, value: Int) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.secondaryText)
            Spacer()
            Text(value.formatted())
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primaryText)
                .monospacedDigit()
        }
    }
}
