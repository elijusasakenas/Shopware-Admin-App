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

    private var apiMessages: [AIMessage] = []
    private let service = AIChatService()
    private let client: ShopwareAdminClient
    /// Returns the signed App Store transaction proving the subscription.
    private let entitlementProvider: () async -> String?
    /// Returns the user's own Anthropic API key, if they brought one — that
    /// routes requests directly to Anthropic instead of the proxy.
    private let apiKeyProvider: () -> String?
    /// Safety cap on continuation round trips per user message ("pause_turn").
    private let maxTurns = 8

    init(
        client: ShopwareAdminClient,
        entitlementProvider: @escaping () async -> String?,
        apiKeyProvider: @escaping () -> String? = { nil }
    ) {
        self.client = client
        self.entitlementProvider = entitlementProvider
        self.apiKeyProvider = apiKeyProvider
    }

    var canSend: Bool { !isThinking }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, canSend else { return }
        entries.append(ChatEntry(kind: .user(trimmed)))
        apiMessages.append(.user(trimmed))
        Task { await runLoop() }
    }

    func reset() {
        entries = []
        apiMessages = []
        isThinking = false
    }

    // MARK: - Conversation loop

    private func runLoop() async {
        isThinking = true
        defer { isThinking = false }

        for _ in 0..<maxTurns {
            let response: AIChatResponse
            do {
                // A fresh Admin API token per round trip; Shopware's MCP
                // server accepts standard bearer tokens (~10 min lifetime).
                let mcpToken = try await client.currentAccessToken()
                let apiKey = apiKeyProvider()
                // The subscription proof is only needed on the proxy path.
                let jws = apiKey == nil ? await entitlementProvider() : nil
                response = try await service.send(
                    messages: apiMessages,
                    mcpURL: client.mcpEndpointURL,
                    mcpToken: mcpToken,
                    entitlementJWS: jws,
                    apiKey: apiKey
                )
            } catch {
                if !error.isCancellation {
                    entries.append(ChatEntry(kind: .error(error.shopwareDisplayMessage)))
                }
                return
            }

            AIUsage.record(
                inputTokens: response.usage?.inputTokens ?? 0,
                outputTokens: response.usage?.outputTokens ?? 0
            )

            // Echo the assistant turn back into the history unchanged —
            // MCP tool blocks must round-trip verbatim.
            apiMessages.append(AIMessage(role: "assistant", content: response.content))
            appendEntries(from: response.content)

            // The API pauses long server-side tool loops; re-send to resume.
            guard response.stopReason == "pause_turn" else { return }
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
