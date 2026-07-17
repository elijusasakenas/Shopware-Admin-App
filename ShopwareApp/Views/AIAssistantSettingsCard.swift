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
    @State private var keyDraft = ""
    @State private var providerSelection = AIProviderSelection.automatic
    @State private var keyError: String?

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
                    ? "\(aiKey.provider?.displayName ?? String(localized: "Saved")) · \(String(localized: "Saved in Keychain"))"
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
            Text("Counted on this device; resets monthly. With your own API key, billing lives in your selected provider's console.")
                .font(.caption)
                .foregroundStyle(Color.secondaryText)

            Divider()

            ownKeySection

            Divider()

            manageSubscriptionButton
            Button {
                Task { await subscriptions.restorePurchases() }
            } label: {
                Text("Restore purchases")
                    .font(.subheadline)
                    .foregroundStyle(Color.shopwareBlue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.border, lineWidth: 1))
        .onAppear {
            usage = AIUsage.snapshot()
            if let provider = aiKey.provider {
                providerSelection = AIProviderSelection(provider: provider)
            }
        }
    }

    private var ownKeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Use your own AI provider key")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.primaryText)
            Text("Use an Anthropic, OpenAI, or Gemini key with or without a subscription. A saved key takes priority for model requests. Remove it anytime to use your active subscription again.")
                .font(.footnote)
                .foregroundStyle(Color.secondaryText)

            Picker("AI provider", selection: $providerSelection) {
                ForEach(AIProviderSelection.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)

            SecureField("Paste API key", text: $keyDraft)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.controlBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.border, lineWidth: 1)
                )

            Button {
                saveKey()
            } label: {
                Text(aiKey.hasKey
                     ? String(localized: "Replace API key")
                     : String(localized: "Save API key"))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .foregroundStyle(Color.primaryText)
                    .background(Color.controlBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if aiKey.hasKey {
                Button(role: .destructive) {
                    removeKey()
                } label: {
                    Text("Remove API key")
                        .font(.subheadline)
                        .foregroundStyle(Color.red)
                }
            }
            if let keyError { ErrorBanner(message: keyError) }
        }
    }

    private func saveKey() {
        do {
            try aiKey.save(keyDraft, provider: providerSelection.provider)
            if let provider = aiKey.provider {
                providerSelection = AIProviderSelection(provider: provider)
            }
            keyDraft = ""
            keyError = nil
        } catch {
            keyError = error.shopwareDisplayMessage
        }
    }

    private func removeKey() {
        do {
            try aiKey.clear()
            keyError = nil
        } catch {
            keyError = error.shopwareDisplayMessage
        }
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
