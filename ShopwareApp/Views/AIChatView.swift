//
//  AIChatView.swift
//  ShopwareApp
//
//  The AI shop assistant: routes between the paywall, the MCP requirement
//  screen, and the chat. The assistant works through Shopware's built-in MCP
//  server, so it is only available on shops that expose it (6.7.11+ with the
//  MCP_SERVER feature flag enabled).
//

import SwiftUI

/// Entry point pushed from the dashboard. Shows the paywall until the
/// subscription is active, verifies the shop's MCP server, then the chat.
struct AIChatScreen: View {
    @ObservedObject var viewModel: ShopwareDashboardViewModel
    @StateObject private var subscriptions = AISubscriptionManager()
    @StateObject private var aiKey = AIKeyStore()
    @State private var mcpAvailability: ShopwareAdminClient.MCPAvailability?
    @State private var serviceAvailability: AIChatService.Availability?

    var body: some View {
        Group {
            if !subscriptions.hasLoadedEntitlements {
                loadingView
            } else if !subscriptions.isSubscribed && !aiKey.hasKey {
                AIPaywallView(subscriptions: subscriptions, aiKey: aiKey)
            } else if serviceAvailability == nil {
                loadingView.task { serviceAvailability = await AIChatService().availability() }
            } else if serviceAvailability == .disabled {
                requirementView(
                    icon: "pause.circle",
                    title: "AI assistant unavailable",
                    message: String(localized: "The AI assistant is temporarily disabled. Please try again later.")
                )
            } else if case .failed(let message) = serviceAvailability {
                requirementView(icon: "wifi.exclamationmark", title: "Couldn't reach the AI service", message: message)
            } else if let client = viewModel.apiClient {
                switch mcpAvailability {
                case .none:
                    loadingView.task { mcpAvailability = await client.mcpAvailability() }
                case .available:
                    AIChatView(client: client, subscriptions: subscriptions, aiKey: aiKey)
                case .unsupportedVersion(let current, let required):
                    requirementView(
                        icon: "arrow.up.circle",
                        title: "Shopware update required",
                        message: String(localized: "The AI assistant needs Shopware \(required) or newer. Your shop runs \(current).")
                    )
                case .disabled:
                    requirementView(
                        icon: "wrench.adjustable",
                        title: "MCP server is disabled",
                        message: String(localized: "Your Shopware version supports the AI assistant, but the MCP server is off. Enable the MCP_SERVER feature flag on your shop, then try again.")
                    )
                case .failed(let message):
                    requirementView(icon: "wifi.exclamationmark", title: "Couldn't check your shop", message: message)
                }
            } else {
                Text("Connect a shop first.")
                    .foregroundStyle(Color.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.appBackground)
        .navigationTitle("AI Assistant")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var loadingView: some View {
        ProgressView()
            .tint(.shopwareBlue)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func requirementView(icon: String, title: LocalizedStringKey, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(Color.shopwareBlue)
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.primaryText)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)
            Button {
                mcpAvailability = nil
                serviceAvailability = nil
            } label: {
                Text("Try again")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.shopwareBlue)
            }
            .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AIChatView: View {
    @StateObject private var chat: AIChatViewModel
    @ObservedObject private var aiKey: AIKeyStore
    @State private var draft = ""
    @State private var keyError: String?
    @FocusState private var inputFocused: Bool

    init(client: ShopwareAdminClient, subscriptions: AISubscriptionManager, aiKey: AIKeyStore) {
        self.aiKey = aiKey
        _chat = StateObject(wrappedValue: AIChatViewModel(
            client: client,
            entitlementProvider: { await subscriptions.entitlementJWS() },
            apiKeyProvider: { aiKey.read() }
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            transcript
            inputBar
        }
        .background(Color.appBackground)
        .confirmationDialog(
            "Approve shop changes?",
            isPresented: Binding(
                get: { chat.pendingApproval != nil },
                set: { if !$0, chat.pendingApproval != nil { chat.declinePendingChange() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Approve exact change") { chat.approvePendingChange() }
            Button("Decline", role: .cancel) { chat.declinePendingChange() }
        } message: {
            Text(chat.pendingApproval?.displaySummary ?? "")
        }
        .alert("Could not remove API key", isPresented: Binding(
            get: { keyError != nil },
            set: { if !$0 { keyError = nil } }
        )) {
            Button("OK", role: .cancel) { keyError = nil }
        } message: {
            Text(keyError ?? "")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if chat.isThinking {
                    Button(role: .cancel) {
                        chat.cancel()
                    } label: {
                        Label("Stop", systemImage: "stop.circle")
                    }
                } else {
                    Button {
                        chat.reset()
                    } label: {
                        Label("New chat", systemImage: "square.and.pencil")
                    }
                    .disabled(chat.entries.isEmpty)
                }
            }
            if aiKey.hasKey {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(role: .destructive) {
                            do {
                                try aiKey.clear()
                            } catch {
                                keyError = error.shopwareDisplayMessage
                            }
                        } label: {
                            Label("Remove API key", systemImage: "key.slash")
                        }
                    } label: {
                        Label("Options", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if chat.entries.isEmpty {
                        emptyState
                    }
                    ForEach(chat.entries) { entry in
                        entryView(entry)
                            .id(entry.id)
                    }
                    if chat.isThinking {
                        HStack(spacing: 8) {
                            ProgressView().tint(.shopwareBlue)
                            Text("Thinking...")
                                .font(.footnote)
                                .foregroundStyle(Color.secondaryText)
                        }
                        .padding(.horizontal, 4)
                        .id("thinking")
                    }
                }
                .padding(16)
            }
            .onChange(of: chat.entries) { _ in
                withAnimation { proxy.scrollTo(chat.entries.last?.id, anchor: .bottom) }
            }
            .onChange(of: chat.isThinking) { thinking in
                if thinking { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(Color.shopwareBlue)
            Text("Ask me anything about your shop.")
                .font(.headline)
                .foregroundStyle(Color.primaryText)
            Text("I work through your shop's own MCP server: products, orders, promotions, settings and more. Every write needs a separate native approval before it can reach your shop.")
                .font(.subheadline)
                .foregroundStyle(Color.secondaryText)
            VStack(alignment: .leading, spacing: 6) {
                suggestion(String(localized: "How did the shop do today?"))
                suggestion(String(localized: "Which products are low on stock?"))
                suggestion(String(localized: "Activate the summer promotion"))
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 24)
    }

    private func suggestion(_ text: String) -> some View {
        Button {
            draft = text
        } label: {
            Text(text)
                .font(.footnote)
                .foregroundStyle(Color.shopwareBlue)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.controlBackground)
                .clipShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }

    @ViewBuilder
    private func entryView(_ entry: ChatEntry) -> some View {
        switch entry.kind {
        case .user(let text):
            HStack {
                Spacer(minLength: 48)
                Text(text)
                    .foregroundStyle(Color.inverseText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.shopwareBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        case .assistant(let text):
            HStack {
                Text(.init(text)) // render the model's markdown
                    .foregroundStyle(Color.primaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.border, lineWidth: 1)
                    )
                Spacer(minLength: 48)
            }
        case .toolActivity(let label, let failed):
            HStack(spacing: 6) {
                Image(systemName: failed ? "exclamationmark.triangle" : "wrench.and.screwdriver")
                    .font(.caption2)
                Text(label)
                    .font(.caption)
            }
            .foregroundStyle(failed ? Color.errorText : Color.secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.controlBackground)
            .clipShape(Capsule())
        case .error(let message):
            ErrorBanner(message: message)
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Message your shop assistant", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.border, lineWidth: 1)
                )
                .onSubmit(sendDraft)
            Button(action: sendDraft) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? Color.shopwareBlue : Color.secondaryText.opacity(0.4))
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.appBackground)
    }

    private var canSend: Bool {
        chat.canSend && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendDraft() {
        guard canSend else { return }
        chat.send(draft)
        draft = ""
    }
}
