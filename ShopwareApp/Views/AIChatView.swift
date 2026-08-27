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

/// Entry point pushed from the dashboard. A personal key works with or without
/// a subscription and takes priority when both are available.
struct AIChatScreen: View {
    @ObservedObject var viewModel: ShopwareDashboardViewModel
    let initialDraft: String
    @StateObject private var subscriptions = AISubscriptionManager()
    @StateObject private var aiKey = AIKeyStore()
    @State private var mcpAvailability: ShopwareAdminClient.MCPAvailability?
    @State private var serviceAvailability: AIChatService.Availability?

    init(viewModel: ShopwareDashboardViewModel, initialDraft: String = "") {
        self.viewModel = viewModel
        self.initialDraft = initialDraft
    }

    var body: some View {
        Group {
            if !subscriptions.hasLoadedEntitlements {
                loadingView
            } else if accessMode == .unavailable {
                AIPaywallView(subscriptions: subscriptions, aiKey: aiKey)
            } else if serviceAvailability == nil {
                loadingView.task { serviceAvailability = await AIChatService().availability() }
            } else if serviceAvailability == .disabled {
                requirementView(
                    icon: "pause.circle",
                    title: "AI assistant unavailable",
                    message: AppLocalization.string("The AI assistant is temporarily disabled. Please try again later.")
                )
            } else if case .failed(let message) = serviceAvailability {
                requirementView(icon: "wifi.exclamationmark", title: "Couldn't reach the AI service", message: message)
            } else if let client = viewModel.apiClient {
                switch mcpAvailability {
                case .none:
                    loadingView.task { mcpAvailability = await client.mcpAvailability() }
                case .available:
                    AIChatView(
                        client: client,
                        subscriptions: subscriptions,
                        aiKey: aiKey,
                        initialDraft: initialDraft
                    )
                case .unsupportedVersion(let current, let required):
                    requirementView(
                        icon: "arrow.up.circle",
                        title: "Shopware update required",
                        message: AppLocalization.string("The AI assistant needs Shopware \(required) or newer. Your shop runs \(current).")
                    )
                case .disabled:
                    requirementView(
                        icon: "wrench.adjustable",
                        title: "MCP server is disabled",
                        message: AppLocalization.string("Your Shopware version supports the AI assistant, but the MCP server is off. Enable the MCP_SERVER feature flag on your shop, then try again.")
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

    private var accessMode: AIAssistantAccessMode {
        AIAssistantAccessMode(
            isSubscribed: subscriptions.isSubscribed,
            hasPersonalKey: aiKey.hasKey
        )
    }

    private var loadingView: some View {
        ProgressView()
            .tint(.shopwareBlue)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func requirementView(icon: String, title: LocalizedStringKey, message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.primaryText)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.secondaryText)
                .lineSpacing(5)
            Button {
                mcpAvailability = nil
                serviceAvailability = nil
            } label: {
                Text("TRY AGAIN")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
            }
            .buttonStyle(IndustryActionButtonStyle(outlined: true))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AIChatView: View {
    @StateObject private var chat: AIChatViewModel
    @ObservedObject private var aiKey: AIKeyStore
    private let initialDraft: String
    @State private var draft = ""
    @State private var keyError: String?
    @State private var didSendInitialDraft = false

    init(
        client: ShopwareAdminClient,
        subscriptions: AISubscriptionManager,
        aiKey: AIKeyStore,
        initialDraft: String = ""
    ) {
        self.aiKey = aiKey
        self.initialDraft = initialDraft
        _draft = State(initialValue: initialDraft)
        _chat = StateObject(wrappedValue: AIChatViewModel(
            client: client,
            entitlementProvider: { await subscriptions.entitlementJWS() },
            credentialProvider: { aiKey.read() }
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            transcript
            inputBar
        }
        .background(Color.appBackground)
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
        .task {
            chat.prepareSession()
            sendInitialDraftIfNeeded()
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
                    if let approval = chat.pendingApproval {
                        InlineApprovalCard(
                            approval: approval,
                            approve: chat.approvePendingChange,
                            decline: chat.declinePendingChange
                        )
                        .id("approval")
                    }
                    if chat.isThinking {
                        Text("WORKING · READING SHOP DATA")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.secondaryText)
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
            Text("Ask, and it works the shop for you.")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.primaryText)
            Text("Runs through your shop's own MCP server — products, orders, promotions, settings. Reads are immediate. Every write stops at an approval gate with the exact arguments shown.")
                .font(.subheadline)
                .foregroundStyle(Color.secondaryText)
                .lineSpacing(5)
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                suggestion(AppLocalization.string("How did the shop do today?"))
                suggestion(AppLocalization.string("Which products are low on stock?"))
                suggestion(AppLocalization.string("Activate the summer promotion"))
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 24)
        .shopwareCard()
    }

    private func suggestion(_ text: String) -> some View {
        Button {
            chat.send(text)
        } label: {
            HStack {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Color.primaryText)
                Spacer()
                Text("ASK")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.shopwareBlue)
            }
            .frame(minHeight: 46)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.border.opacity(0.55)).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func entryView(_ entry: ChatEntry) -> some View {
        switch entry.kind {
        case .user(let text):
            VStack(alignment: .leading, spacing: 5) {
                Text("You").font(.caption.weight(.semibold)).foregroundStyle(Color.secondaryText)
                Text(text)
                    .font(.body)
                    .foregroundStyle(Color.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.shopwareBlue.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        case .assistant(let text):
            VStack(alignment: .leading, spacing: 5) {
                Text("Assistant").font(.caption.weight(.semibold)).foregroundStyle(Color.secondaryText)
                Text(.init(text)) // render the model's markdown
                    .font(.body)
                    .foregroundStyle(Color.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.border, lineWidth: 1)
                    )
            }
        case .toolActivity(let label, let failed):
            Text((failed ? "FAILED · " : "WORKING · ") + label.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(failed ? Color.primaryText : Color.secondaryText)
        case .error(let message):
            ErrorBanner(message: message)
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        AskBar(
            draft: $draft,
            autoFocus: initialDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onSubmit: sendDraft
        )
            .opacity(chat.canSend ? 1 : 0.45)
    }

    private var canSend: Bool {
        chat.canSend && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendDraft() {
        guard canSend else { return }
        chat.send(draft)
        draft = ""
    }

    private func sendInitialDraftIfNeeded() {
        guard !didSendInitialDraft else { return }
        didSendInitialDraft = true
        guard !initialDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        sendDraft()
    }
}

private struct InlineApprovalCard: View {
    let approval: AIApprovalChallenge
    let approve: () -> Void
    let decline: () -> Void

    var body: some View {
        BlueprintFrame {
            VStack(alignment: .leading, spacing: 12) {
                Text("Approval required · Write")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.shopwareBlue)
                Text(approval.actions.count == 1 ? approval.actions[0].localizedTitle : "\(approval.actions.count) shop changes")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.primaryText)
                Divider()
                ForEach(approval.actions) { action in
                    Text(action.formattedDetails)
                        .font(.caption)
                        .foregroundStyle(Color.secondaryText)
                        .textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    Button(action: approve) {
                        Text("APPROVE ONCE")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(IndustryActionButtonStyle())
                    Button(action: decline) {
                        Text("DECLINE")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(IndustryActionButtonStyle(outlined: true))
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.shopwareBlue, lineWidth: 1)
        )
    }
}
