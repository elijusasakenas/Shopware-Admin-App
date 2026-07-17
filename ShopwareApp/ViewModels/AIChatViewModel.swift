//
//  AIChatViewModel.swift
//  ShopwareApp
//
//  Conversation state for the AI assistant. The model operates the shop
//  through Shopware's built-in MCP server (Shopware 6.7.11+), so tool calls
//  execute server-side; this view model relays the conversation, surfaces
//  tool activity, and resumes paused turns.
//

import Combine
import Foundation

@MainActor
final class AIChatViewModel: ObservableObject {
    @Published var entries: [ChatEntry] = []
    @Published var isThinking = false
    @Published var pendingApproval: AIApprovalChallenge?

    private var apiMessages: [AIMessage] = []
    private let service: AIChatService
    private let client: ShopwareAdminClient
    /// Returns the signed App Store transaction proving the subscription.
    private let entitlementProvider: () async -> String?
    /// Returns the user's own provider credential, if they brought one. Model
    /// requests go directly to that provider; MCP still uses the approval
    /// gateway.
    private let credentialProvider: () -> AIProviderCredential?
    /// Safety cap on continuation round trips per user message ("pause_turn").
    private let maxTurns = 8
    private var activeTask: Task<Void, Never>?
    private var conversationID = UUID()

    init(
        client: ShopwareAdminClient,
        entitlementProvider: @escaping () async -> String?,
        credentialProvider: @escaping () -> AIProviderCredential? = { nil },
        service: AIChatService? = nil
    ) {
        self.client = client
        self.entitlementProvider = entitlementProvider
        self.credentialProvider = credentialProvider
        self.service = service ?? AIChatService()
    }

    var canSend: Bool { !isThinking && pendingApproval == nil }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, canSend else { return }
        entries.append(ChatEntry(kind: .user(trimmed)))
        apiMessages.append(.user(trimmed))
        startRun()
    }

    func reset() {
        activeTask?.cancel()
        activeTask = nil
        conversationID = UUID()
        entries = []
        apiMessages = []
        pendingApproval = nil
        isThinking = false
    }

    func cancel() {
        guard isThinking else { return }
        activeTask?.cancel()
        activeTask = nil
        conversationID = UUID()
        isThinking = false
        entries.append(ChatEntry(kind: .error(String(localized: "Request cancelled."))))
    }

    func approvePendingChange() {
        guard let approval = pendingApproval else { return }
        guard approval.expiresAt > Int64(Date().timeIntervalSince1970 * 1_000) else {
            pendingApproval = nil
            entries.append(ChatEntry(kind: .error(String(localized: "The approval expired. Ask the assistant to prepare the change again."))))
            return
        }
        pendingApproval = nil
        let message = String(localized: "Approved the proposed change.")
        entries.append(ChatEntry(kind: .user(message)))
        apiMessages.append(.user("The user approved the exact proposed action in the native confirmation. Retry it once with identical arguments."))
        startRun(approvalToken: approval.token)
    }

    func declinePendingChange() {
        guard pendingApproval != nil else { return }
        pendingApproval = nil
        let message = String(localized: "Declined the proposed change.")
        entries.append(ChatEntry(kind: .user(message)))
        apiMessages.append(.user("The user declined the proposed write. Do not perform or retry it."))
    }

    // MARK: - Conversation loop

    private func startRun(approvalToken: String? = nil) {
        guard activeTask == nil, !isThinking else { return }
        let id = conversationID
        isThinking = true
        activeTask = Task { [weak self] in
            await self?.runLoop(conversationID: id, approvalToken: approvalToken)
        }
    }

    private func runLoop(conversationID id: UUID, approvalToken: String?) async {
        var nextApprovalToken = approvalToken
        defer {
            if conversationID == id {
                isThinking = false
                activeTask = nil
            }
        }

        for _ in 0..<maxTurns {
            let response: AIChatResponse
            do {
                // A fresh Admin API token per round trip; Shopware's MCP
                // server accepts standard bearer tokens (~10 min lifetime).
                let mcpToken = try await client.currentAccessToken()
                let credential = credentialProvider()
                // The subscription proof is only needed on the proxy path.
                let jws = credential == nil ? await entitlementProvider() : nil
                try Task.checkCancellation()
                guard conversationID == id else { return }
                response = try await service.send(
                    messages: apiMessages,
                    mcpURL: client.mcpEndpointURL,
                    mcpToken: mcpToken,
                    entitlementJWS: jws,
                    credential: credential,
                    approvalToken: nextApprovalToken
                )
                nextApprovalToken = nil // approval grants are one-time
                try Task.checkCancellation()
                guard conversationID == id else { return }
            } catch {
                if !error.isCancellation {
                    entries.append(ChatEntry(kind: .error(error.shopwareDisplayMessage)))
                }
                return
            }

            AIUsage.record(
                inputTokens: response.usage?.totalInputTokens ?? 0,
                outputTokens: response.usage?.outputTokens ?? 0
            )

            // Echo the assistant turn back into the history unchanged —
            // MCP tool blocks must round-trip verbatim.
            apiMessages.append(AIMessage(role: "assistant", content: response.content))
            appendEntries(from: response.content)

            if let approval = response.approval, !approval.actions.isEmpty {
                pendingApproval = approval
                return
            }

            switch response.stopReason {
            case "pause_turn":
                continue
            case "max_tokens":
                entries.append(ChatEntry(kind: .error(String(localized: "The response reached its length limit. Ask the assistant to continue more briefly."))))
                return
            case "refusal":
                entries.append(ChatEntry(kind: .error(String(localized: "The assistant could not complete that request."))))
                return
            case "end_turn", "stop_sequence", .none:
                return
            default:
                entries.append(ChatEntry(kind: .error(String(localized: "The assistant stopped unexpectedly. Please try again."))))
                return
            }
        }

        entries.append(ChatEntry(kind: .error(String(localized: "The assistant stopped after too many steps. Please refine your request."))))
    }

    /// Renders text blocks as bubbles and MCP tool calls as activity chips.
    private func appendEntries(from content: [AIContentBlock]) {
        // Tool results carry is_error; map them back to the call they answer.
        var failedToolUseIDs: Set<String> = []
        for block in content {
            if case .other(let raw) = block,
               raw["type"]?.stringValue == "mcp_tool_result",
               raw["is_error"]?.boolValue == true,
               let id = raw["tool_use_id"]?.stringValue {
                failedToolUseIDs.insert(id)
            }
        }

        for block in content {
            switch block {
            case .text(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { entries.append(ChatEntry(kind: .assistant(trimmed))) }
            case .other(let raw) where raw["type"]?.stringValue == "mcp_tool_use":
                let name = raw["name"]?.stringValue ?? "tool"
                let id = raw["id"]?.stringValue ?? ""
                entries.append(ChatEntry(kind: .toolActivity(
                    label: Self.displayName(forTool: name),
                    failed: failedToolUseIDs.contains(id)
                )))
            case .toolUse, .toolResult, .other:
                break
            }
        }
    }

    /// "product-search" → "product search" for the activity chip.
    static func displayName(forTool name: String) -> String {
        name.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }
}
