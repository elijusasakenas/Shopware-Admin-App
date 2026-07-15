//
//  AIChatService.swift
//  ShopwareApp
//
//  Subscription requests use the AI proxy. BYOK requests call Anthropic
//  directly, but still use the proxy's short-lived MCP approval gateway so a
//  model can never commit a Shopware write without native user approval.
//

import Foundation

enum AIProxyConfig {
    static let overrideKey = "aiProxyURL"
    static let clientIDKey = "aiProxyClientID"
    static let defaultURLString = "https://shopware-ai-proxy.elijusasakenas.workers.dev"

    static var baseURL: URL? {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: overrideKey),
           let url = URL(string: override), !override.isEmpty {
            return url
        }
        #endif
        guard let url = URL(string: defaultURLString),
              url.scheme == "https", url.user == nil, url.password == nil else { return nil }
        return url
    }

    static var clientID: String {
        if let value = UserDefaults.standard.string(forKey: clientIDKey), !value.isEmpty { return value }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: clientIDKey)
        return value
    }
}

struct AIChatService {
    var session: URLSession = .shared

    enum Availability: Equatable {
        case enabled
        case disabled
        case failed(String)
    }

    static let directModel = "claude-opus-4-8"
    static let directSystemPrompt = """
    You are the AI assistant inside a Shopware merchant app. Use the connected Shopware MCP server instead of guessing and look up entities before acting.

    Write operations are protected by a native approval gateway. Explain the exact proposed change first. A commit without approval will be blocked. After native approval, retry the exact same tool name and arguments once. Never claim success unless the tool result confirms it.

    Be concise and practical, answer in the user's language, and ask when a request is ambiguous.
    """

    func availability() async -> Availability {
        struct Configuration: Decodable { let enabled: Bool }
        guard let baseURL = AIProxyConfig.baseURL else { return .failed("The AI service URL is not configured securely.") }
        var request = URLRequest(url: baseURL.appending(path: "/v1/config"))
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let configuration = try await perform(request, as: Configuration.self)
            return configuration.enabled ? .enabled : .disabled
        } catch {
            return .failed(error.shopwareDisplayMessage)
        }
    }

    func send(
        messages: [AIMessage],
        mcpURL: URL,
        mcpToken: String,
        entitlementJWS: String?,
        apiKey: String? = nil,
        approvalToken: String? = nil
    ) async throws -> AIChatResponse {
        guard mcpURL.scheme == "https" else {
            throw ShopwareAPIError.message("The Shopware MCP endpoint must use HTTPS.")
        }
        if let apiKey {
            return try await sendDirect(
                messages: messages,
                mcpURL: mcpURL,
                mcpToken: mcpToken,
                apiKey: apiKey,
                approvalToken: approvalToken
            )
        }
        return try await sendViaProxy(
            messages: messages,
            mcpURL: mcpURL,
            mcpToken: mcpToken,
            entitlementJWS: entitlementJWS,
            approvalToken: approvalToken
        )
    }

    private func sendViaProxy(
        messages: [AIMessage],
        mcpURL: URL,
        mcpToken: String,
        entitlementJWS: String?,
        approvalToken: String?
    ) async throws -> AIChatResponse {
        struct Body: Encodable {
            let messages: [AIMessage]
            let mcpURL: String
            let mcpToken: String
            let clientID: String
            let approvalToken: String?

            private enum CodingKeys: String, CodingKey {
                case messages
                case mcpURL = "mcp_url"
                case mcpToken = "mcp_token"
                case clientID = "client_id"
                case approvalToken = "approval_token"
            }
        }

        var request = try proxyRequest(path: "/v1/chat")
        if let entitlementJWS { request.setValue(entitlementJWS, forHTTPHeaderField: "X-App-Transaction") }
        request.httpBody = try JSONEncoder().encode(Body(
            messages: messages,
            mcpURL: mcpURL.absoluteString,
            mcpToken: mcpToken,
            clientID: AIProxyConfig.clientID,
            approvalToken: approvalToken
        ))
        return try await perform(request, as: AIChatResponse.self)
    }

    private func sendDirect(
        messages: [AIMessage],
        mcpURL: URL,
        mcpToken: String,
        apiKey: String,
        approvalToken: String?
    ) async throws -> AIChatResponse {
        let capability = try await gatewayCapability(
            mcpURL: mcpURL,
            mcpToken: mcpToken,
            approvalToken: approvalToken
        )
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("mcp-client-2025-11-20", forHTTPHeaderField: "anthropic-beta")

        let messagesJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(messages))
        request.httpBody = try JSONSerialization.data(withJSONObject: [
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
                "url": capability.url,
                "authorization_token": capability.token
            ]],
            "tools": [["type": "mcp_toolset", "mcp_server_name": "shopware"]],
            "messages": messagesJSON
        ])

        let response = try await perform(request, as: AIChatResponse.self)
        let approval = try await directApproval(
            content: response.content,
            mcpURL: mcpURL,
            previousApprovalToken: approvalToken
        )
        return AIChatResponse(
            content: response.content,
            stopReason: response.stopReason,
            usage: response.usage,
            approval: approval
        )
    }

    private struct GatewayCapability: Decodable {
        let url: String
        let token: String
    }

    private func gatewayCapability(
        mcpURL: URL,
        mcpToken: String,
        approvalToken: String?
    ) async throws -> GatewayCapability {
        struct Body: Encodable {
            let mcpURL: String
            let mcpToken: String
            let clientID: String
            let approvalToken: String?
            enum CodingKeys: String, CodingKey {
                case mcpURL = "mcp_url", mcpToken = "mcp_token", clientID = "client_id"
                case approvalToken = "approval_token"
            }
        }
        var request = try proxyRequest(path: "/v1/capability")
        request.httpBody = try JSONEncoder().encode(Body(
            mcpURL: mcpURL.absoluteString,
            mcpToken: mcpToken,
            clientID: AIProxyConfig.clientID,
            approvalToken: approvalToken
        ))
        return try await perform(request, as: GatewayCapability.self)
    }

    private func directApproval(
        content: [AIContentBlock],
        mcpURL: URL,
        previousApprovalToken: String?
    ) async throws -> AIApprovalChallenge? {
        struct Body: Encodable {
            let content: [AIContentBlock]
            let mcpURL: String
            let clientID: String
            let approvalToken: String?
            enum CodingKeys: String, CodingKey {
                case content, mcpURL = "mcp_url", clientID = "client_id"
                case approvalToken = "approval_token"
            }
        }
        struct Wrapper: Decodable { let approval: AIApprovalChallenge? }
        var request = try proxyRequest(path: "/v1/approval")
        request.httpBody = try JSONEncoder().encode(Body(
            content: content,
            mcpURL: mcpURL.absoluteString,
            clientID: AIProxyConfig.clientID,
            approvalToken: previousApprovalToken
        ))
        return try await perform(request, as: Wrapper.self).approval
    }

    private func proxyRequest(path: String) throws -> URLRequest {
        guard let baseURL = AIProxyConfig.baseURL else {
            throw ShopwareAPIError.message("The AI service URL is not configured securely.")
        }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            throw ShopwareAPIError.message(errorMessage(from: data, status: status))
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ShopwareAPIError.message("The AI service returned an invalid response.")
        }
    }

    private func errorMessage(from data: Data, status: Int) -> String {
        struct ErrorBody: Decodable {
            struct Inner: Decodable { let message: String }
            let error: Inner
        }
        if let body = try? JSONDecoder().decode(ErrorBody.self, from: data) { return body.error.message }
        switch status {
        case 401: return String(localized: "The AI service rejected the subscription. Try restoring purchases.")
        case 413: return String(localized: "This conversation is too large. Start a new chat.")
        case 429: return String(localized: "Your AI usage limit was reached. Please try again later.")
        case 503: return String(localized: "The AI assistant is temporarily unavailable.")
        default: return String(localized: "The AI service returned an error (\(status)).")
        }
    }
}
