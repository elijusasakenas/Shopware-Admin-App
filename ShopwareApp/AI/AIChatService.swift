//
//  AIChatService.swift
//  ShopwareApp
//
//  Client for the AI chat proxy (see server/ai-proxy). The proxy holds the
//  Anthropic API key, validates the App Store subscription that is sent along
//  as a signed transaction, and forwards the conversation to the model.
//

import Foundation

enum AIProxyConfig {
    /// UserDefaults key that overrides the proxy URL (useful for testing a
    /// local `wrangler dev` instance).
    static let overrideKey = "aiProxyURL"

    /// The deployed ai-proxy worker. Replace with your own deployment URL
    /// before shipping (see server/ai-proxy/README.md).
    static let defaultURLString = "https://shopware-ai-proxy.elijusasakenas.workers.dev"

    static var baseURL: URL? {
        if let override = UserDefaults.standard.string(forKey: overrideKey),
           let url = URL(string: override), !override.isEmpty {
            return url
        }
        return URL(string: defaultURLString)
    }
}

struct AIChatService {
    var session: URLSession = .shared

    /// Model used when the user brings their own Anthropic API key. The
    /// subscription path's model is configured on the proxy instead.
    static let directModel = "claude-opus-4-8"

    /// Mirrors the proxy's system prompt for the bring-your-own-key path.
    static let directSystemPrompt = """
    You are the AI assistant inside a Shopware merchant app. The user is a shop owner managing their store from their phone.

    You are connected to the shop's own MCP server, which exposes Shopware's tools, resources, and prompts. Use them instead of guessing: look up entities before acting on them. Amounts are in the shop's currency.

    Changing the shop requires the user's consent. Before any write (create, update, delete, state change, configuration change): state exactly what you are about to change and ask the user to confirm in chat. Where a tool supports dry-run execution, dry-run first and show the outcome. Only commit after the user clearly agrees. If the user declines, accept it and do not retry.

    Be concise and practical. Answer in the language the user writes in. When you list data, prefer short readable summaries over raw dumps. If a request is ambiguous (e.g. several products match), show the candidates and ask which one the user means.
    """

    /// Sends the conversation and returns the model's reply. Two modes:
    /// - `apiKey` set: the user's own Anthropic key — call the Anthropic API
    ///   directly from the device; no subscription or proxy involved.
    /// - otherwise: route through the AI proxy, authorized by
    ///   `entitlementJWS` (the signed App Store transaction).
    /// Either way the shop's MCP endpoint + short-lived Admin API token ride
    /// along so the model can operate the shop through Shopware's MCP server.
    func send(
        messages: [AIMessage],
        mcpURL: URL,
        mcpToken: String,
        entitlementJWS: String?,
        apiKey: String? = nil
    ) async throws -> AIChatResponse {
        if let apiKey {
            return try await sendDirect(messages: messages, mcpURL: mcpURL, mcpToken: mcpToken, apiKey: apiKey)
        }
        return try await sendViaProxy(messages: messages, mcpURL: mcpURL, mcpToken: mcpToken, entitlementJWS: entitlementJWS)
    }

    // MARK: - Subscription path (proxy)

    private func sendViaProxy(
        messages: [AIMessage],
        mcpURL: URL,
        mcpToken: String,
        entitlementJWS: String?
    ) async throws -> AIChatResponse {
        guard let baseURL = AIProxyConfig.baseURL else {
            throw ShopwareAPIError.message("The AI service URL is not configured.")
        }

        struct Body: Encodable {
            let messages: [AIMessage]
            let mcpURL: String
            let mcpToken: String

            private enum CodingKeys: String, CodingKey {
                case messages
                case mcpURL = "mcp_url"
                case mcpToken = "mcp_token"
            }
        }

        var request = URLRequest(url: baseURL.appending(path: "/v1/chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let entitlementJWS {
            request.setValue(entitlementJWS, forHTTPHeaderField: "X-App-Transaction")
        }
        request.httpBody = try JSONEncoder().encode(
            Body(messages: messages, mcpURL: mcpURL.absoluteString, mcpToken: mcpToken)
        )

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard (200...299).contains(status) else {
            throw ShopwareAPIError.message(errorMessage(from: data, status: status))
        }
        return try JSONDecoder().decode(AIChatResponse.self, from: data)
    }

    // MARK: - Bring-your-own-key path (direct Anthropic API)

    private func sendDirect(
        messages: [AIMessage],
        mcpURL: URL,
        mcpToken: String,
        apiKey: String
    ) async throws -> AIChatResponse {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("mcp-client-2025-11-20", forHTTPHeaderField: "anthropic-beta")

        // Messages are Encodable; re-hydrate them so the request body can be
        // assembled as one JSON object alongside the MCP connector config.
        let messagesJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(messages))
        let body: [String: Any] = [
            "model": Self.directModel,
            "max_tokens": 4096,
            "system": [[
                "type": "text",
                "text": Self.directSystemPrompt,
                "cache_control": ["type": "ephemeral"]
            ]],
            "mcp_servers": [[
                "type": "url",
                "name": "shopware",
                "url": mcpURL.absoluteString,
                "authorization_token": mcpToken
            ]],
            "tools": [["type": "mcp_toolset", "mcp_server_name": "shopware"]],
            "messages": messagesJSON
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard (200...299).contains(status) else {
            // The Anthropic error body has the same { error: { message } } shape.
            throw ShopwareAPIError.message(errorMessage(from: data, status: status))
        }
        return try JSONDecoder().decode(AIChatResponse.self, from: data)
    }

    private func errorMessage(from data: Data, status: Int) -> String {
        struct ErrorBody: Decodable {
            struct Inner: Decodable { let message: String }
            let error: Inner
        }
        if let body = try? JSONDecoder().decode(ErrorBody.self, from: data) {
            return body.error.message
        }
        switch status {
        case 401: return String(localized: "The AI service rejected the subscription. Try restoring purchases.")
        case 429: return String(localized: "The AI service is busy. Please try again in a moment.")
        default: return String(localized: "The AI service returned an error (\(status)).")
        }
    }
}
