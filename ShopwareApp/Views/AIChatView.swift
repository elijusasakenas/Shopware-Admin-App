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
    @StateObject private var subscriptions = AISubscriptionManager()
    @StateObject private var aiKey = AIKeyStore()
    @State private var mcpAvailability: ShopwareAdminClient.MCPAvailability?
    @State private var serviceAvailability: AIChatService.Availability?

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

    private var accessMode: AIAssistantAccessMode {
        AIAssistantAccessMode(
            isSubscribed: subscriptions.isSubscribed,
            hasPersonalKey: aiKey.hasKey
        )
    }

    private var loadingView: some View {
        Text("LOADING…")
            .industryKicker()
            .foregroundStyle(Color.industryFaint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func requirementView(icon: String, title: LocalizedStringKey, message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(IndustryFont.display(28))
                .foregroundStyle(Color.industryText)
            Text(message)
                .font(IndustryFont.body(14))
                .foregroundStyle(Color.industryDim)
                .lineSpacing(5)
            Button {
                mcpAvailability = nil
                serviceAvailability = nil
            } label: {
                Text("TRY AGAIN")
                    .industryKicker(10)
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
    @State private var draft = ""
    @State private var keyError: String?
    @FocusState private var inputFocused: Bool

    init(client: ShopwareAdminClient, subscriptions: AISubscriptionManager, aiKey: AIKeyStore) {
        self.aiKey = aiKey
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
        .background(Color.industryBackground)
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
                            .industryKicker()
                            .foregroundStyle(Color.industryFaint)
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
                .font(IndustryFont.display(26))
                .foregroundStyle(Color.industryText)
            Text("Runs through your shop's own MCP server — products, orders, promotions, settings. Reads are immediate. Every write stops at an approval gate with the exact arguments shown.")
                .font(IndustryFont.body(14))
                .foregroundStyle(Color.industryDim)
                .lineSpacing(5)
            VStack(alignment: .leading, spacing: 0) {
                Rectangle().fill(Color.industryLine).frame(height: 1)
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
            chat.send(text)
        } label: {
            HStack {
                Text(text)
                    .font(IndustryFont.body(14))
                    .foregroundStyle(Color.industryText)
                Spacer()
                Text("ASK")
                    .industryKicker()
                    .foregroundStyle(Color.industryAccent)
            }
            .frame(minHeight: 46)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.industryHair).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func entryView(_ entry: ChatEntry) -> some View {
        switch entry.kind {
        case .user(let text):
            VStack(alignment: .leading, spacing: 5) {
                Text("YOU").industryKicker().foregroundStyle(Color.industryFaint)
                Text(text)
                    .font(IndustryFont.body(14.5))
                    .foregroundStyle(Color.industryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.industryAccentTint)
                    .overlay(Rectangle().stroke(Color.industryLine, lineWidth: 1))
            }
        case .assistant(let text):
            VStack(alignment: .leading, spacing: 5) {
                Text("ASSISTANT").industryKicker().foregroundStyle(Color.industryFaint)
                Text(.init(text)) // render the model's markdown
                    .font(IndustryFont.body(14.5))
                    .foregroundStyle(Color.industryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.industrySurface)
                    .overlay(Rectangle().stroke(Color.industryLine, lineWidth: 1))
            }
        case .toolActivity(let label, let failed):
            Text((failed ? "FAILED · " : "WORKING · ") + label.uppercased())
                .industryKicker()
                .foregroundStyle(failed ? Color.industryText : Color.industryFaint)
        case .error(let message):
            ErrorBanner(message: message)
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        AskBar(draft: $draft, onSubmit: sendDraft)
            .opacity(chat.canSend ? 1 : 0.45)
    }

    private var canSend: Bool {
        chat.canSend && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var approvalPresented: Binding<Bool> {
        Binding(
            get: { chat.pendingApproval != nil },
            set: { isPresented in
                if !isPresented, chat.pendingApproval != nil {
                    chat.declinePendingChange()
                }
            }
        )
    }

    private func sendDraft() {
        guard canSend else { return }
        chat.send(draft)
        draft = ""
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
                    .industryKicker()
                    .foregroundStyle(Color.industryAccent)
                Text(approval.actions.count == 1 ? approval.actions[0].localizedTitle : "\(approval.actions.count) shop changes")
                    .font(IndustryFont.display(22))
                    .foregroundStyle(Color.industryText)
                Rectangle().fill(Color.industryHair).frame(height: 1)
                ForEach(approval.actions) { action in
                    Text(action.formattedDetails)
                        .font(IndustryFont.display(13))
                        .foregroundStyle(Color.industryDim)
                        .textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    Button(action: approve) {
                        Text("APPROVE ONCE")
                            .industryKicker(10)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(IndustryActionButtonStyle())
                    Button(action: decline) {
                        Text("DECLINE")
                            .industryKicker(10)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(IndustryActionButtonStyle(outlined: true))
                }
            }
        }
        .overlay(Rectangle().stroke(Color.industryAccent, lineWidth: 1))
    }
}

private struct AIApprovalReviewSheet: View {
    let approval: AIApprovalChallenge
    let approve: () -> Void
    let decline: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    actionList
                    exactApprovalNotice
                }
                .padding(20)
                .padding(.bottom, 8)
            }
            .background(Color.appBackground)
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
            .navigationTitle("Review AI changes")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .interactiveDismissDisabled()
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: 540, idealWidth: 580, minHeight: 620, idealHeight: 700)
        #endif
    }

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.shopwareBlue.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.shopwareBlue)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 6) {
                Text("Your approval is required")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.primaryText)
                Text("Nothing will be changed in your shop until you review and approve the exact actions below.")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Label(expiryText(at: context.date), systemImage: approval.isExpired(at: context.date) ? "clock.badge.xmark" : "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(approval.isExpired(at: context.date) ? Color.red : Color.amber)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background((approval.isExpired(at: context.date) ? Color.red : Color.amber).opacity(0.1))
                    .clipShape(Rectangle())
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var actionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(approval.actions.count == 1
                 ? String(localized: "PROPOSED CHANGE")
                 : String(localized: "PROPOSED CHANGES"))
                .font(.caption.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(Color.secondaryText)

            ForEach(Array(approval.actions.enumerated()), id: \.element.id) { index, action in
                approvalActionCard(action, number: index + 1)
            }
        }
    }

    private func approvalActionCard(_ action: AIApprovalChallenge.Action, number: Int) -> some View {
        let accent = action.isDestructive ? Color.red : Color.amber
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Rectangle()
                        .fill(accent.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: action.isDestructive ? "trash.fill" : "wand.and.stars")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(accent)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(action.localizedTitle)
                        .font(.headline)
                        .foregroundStyle(Color.primaryText)
                    Text(action.isDestructive
                         ? String(localized: "Destructive action")
                         : String(localized: "Shop data change"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                }
                Spacer(minLength: 8)
                Text("#\(number)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.secondaryText)
            }

            Divider()

            Text(String(localized: "Technical action: \(action.tool)"))
                .font(.caption2.monospaced())
                .foregroundStyle(Color.secondaryText)
                .textSelection(.enabled)

            VStack(alignment: .leading, spacing: 6) {
                Text("Exact details")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.secondaryText)
                Text(action.formattedDetails)
                    .font(.caption.monospaced())
                    .foregroundStyle(Color.primaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color.surface)
        .clipShape(Rectangle())
        .overlay(
            Rectangle()
                .stroke(accent.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var exactApprovalNotice: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.title3)
                .foregroundStyle(Color.shopwareBlue)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("One-time, exact approval")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.primaryText)
                Text("This approval can be used once and only for the actions shown above. Any changed arguments or later action will require a new approval.")
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.shopwareBlue.opacity(0.08))
        .clipShape(Rectangle())
    }

    private var actionBar: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 10) {
                Divider()
                Button(action: approve) {
                    Label(
                        approval.actions.count == 1
                            ? String(localized: "Approve and apply")
                            : String(localized: "Approve \(approval.actions.count) changes"),
                        systemImage: "checkmark.shield.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(Color.inverseText)
                    .background(Color.shopwareBlue.opacity(approval.isExpired(at: context.date) ? 0.4 : 1))
                    .clipShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(approval.isExpired(at: context.date))

                Button(role: .cancel, action: decline) {
                    Text("Do not apply")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primaryText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.controlBackground)
                        .clipShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .background(.regularMaterial)
        }
    }

    private func expiryText(at date: Date) -> String {
        let seconds = max(0, Int(approval.expirationDate.timeIntervalSince(date)))
        guard seconds > 0 else { return String(localized: "Approval expired") }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return minutes > 0
            ? String(localized: "Expires in \(minutes)m \(remainder)s")
            : String(localized: "Expires in \(remainder)s")
    }
}
