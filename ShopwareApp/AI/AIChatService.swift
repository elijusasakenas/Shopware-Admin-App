//
//  AIChatService.swift
//  ShopwareApp
//
//  Subscription requests use the AI proxy. BYOK requests call the selected
//  AI provider directly, but still use the proxy's short-lived MCP approval
//  gateway so a model can never commit a Shopware write without native user
//  approval.
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

    static let anthropicModel = "claude-opus-4-8"
    static let openAIModel = "gpt-5.6"
    static let geminiModel = "gemini-3.5-flash"
    static let directSystemPrompt = """
    You are the AI assistant inside a Shopware merchant app. Use the connected Shopware MCP server instead of guessing and look up entities before acting.

    Write operations are protected by a native approval gateway. Explain the exact proposed change first. A commit without approval will be blocked. After native approval, retry the exact same tool name and arguments once. Never claim success unless the tool result confirms it.

    Be concise and practical, answer in the user's language, and ask when a request is ambiguous.
    """

    func availability() async -> Availability {
        struct Configuration: Decodable { let enabled: Bool }
        struct LegacyHealth: Decodable {
            let ok: Bool
            let enabled: Bool?
        }

        guard let baseURL = AIProxyConfig.baseURL else { return .failed("The AI service URL is not configured securely.") }
        var request = URLRequest(url: baseURL.appending(path: "/v1/config"))
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200...299).contains(status) {
                guard let configuration = try? JSONDecoder().decode(Configuration.self, from: data) else {
                    throw ShopwareAPIError.message("The AI service returned an invalid response.")
                }
                return configuration.enabled ? .enabled : .disabled
            }

            // Workers deployed before the remote feature flag was introduced
            // expose only /health. Keep those deployments usable while making
            // /v1/config the authoritative endpoint for current versions.
            guard status == 404 else {
                throw ShopwareAPIError.message(errorMessage(from: data, status: status))
            }
            var healthRequest = URLRequest(url: baseURL.appending(path: "/health"))
            healthRequest.timeoutInterval = 15
            healthRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            let (healthData, healthResponse) = try await session.data(for: healthRequest)
            let healthStatus = (healthResponse as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(healthStatus) else {
                throw ShopwareAPIError.message(errorMessage(from: healthData, status: healthStatus))
            }
            guard let health = try? JSONDecoder().decode(LegacyHealth.self, from: healthData) else {
                throw ShopwareAPIError.message("The AI service returned an invalid response.")
            }
            let enabled = health.enabled ?? health.ok
            return enabled ? .enabled : .disabled
        } catch {
            return .failed(error.shopwareDisplayMessage)
        }
    }

    func send(
        messages: [AIMessage],
        mcpURL: URL,
        mcpToken: String,
        entitlementJWS: String?,
        credential: AIProviderCredential? = nil,
        approvalToken: String? = nil
    ) async throws -> AIChatResponse {
        guard mcpURL.scheme == "https" else {
            throw ShopwareAPIError.message("The Shopware MCP endpoint must use HTTPS.")
        }
        if let credential {
            return try await sendDirect(
                messages: messages,
                mcpURL: mcpURL,
                mcpToken: mcpToken,
                credential: credential,
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

        guard let entitlementJWS else {
            throw ShopwareAPIError.message("A verified subscription is required to use the included AI service.")
        }
        guard let baseURL = AIProxyConfig.baseURL else {
            throw ShopwareAPIError.message("The AI service URL is not configured securely.")
        }
        let clientID = AIProxyConfig.clientID
        let body = try JSONEncoder().encode(Body(
            messages: messages,
            mcpURL: mcpURL.absoluteString,
            mcpToken: mcpToken,
            clientID: clientID,
            approvalToken: approvalToken
        ))
        let appAttest = try await AppAttestManager.shared.headers(
            baseURL: baseURL,
            body: body,
            entitlementJWS: entitlementJWS,
            clientID: clientID,
            session: session
        )
        var request = try proxyRequest(path: "/v1/chat")
        request.setValue(entitlementJWS, forHTTPHeaderField: "X-App-Transaction")
        request.setValue(appAttest.keyID, forHTTPHeaderField: "X-App-Attest-Key-ID")
        request.setValue(appAttest.challenge, forHTTPHeaderField: "X-App-Attest-Challenge")
        request.setValue(appAttest.assertion, forHTTPHeaderField: "X-App-Attest-Assertion")
        request.httpBody = body
        return try await perform(request, as: AIChatResponse.self)
    }

    private func sendDirect(
        messages: [AIMessage],
        mcpURL: URL,
        mcpToken: String,
        credential: AIProviderCredential,
        approvalToken: String?
    ) async throws -> AIChatResponse {
        switch credential.provider {
        case .anthropic:
            return try await sendAnthropic(
                messages: messages,
                mcpURL: mcpURL,
                mcpToken: mcpToken,
                apiKey: credential.key,
                approvalToken: approvalToken
            )
        case .openAI:
            return try await sendOpenAI(
                messages: messages,
                mcpURL: mcpURL,
                mcpToken: mcpToken,
                apiKey: credential.key,
                approvalToken: approvalToken
            )
        case .gemini:
            return try await sendGemini(
                messages: messages,
                mcpURL: mcpURL,
                mcpToken: mcpToken,
                apiKey: credential.key,
                approvalToken: approvalToken
            )
        }
    }

    private func sendAnthropic(
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
            "model": Self.anthropicModel,
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

        let response = try await perform(
            request,
            as: AIChatResponse.self,
            unauthorizedMessage: providerKeyError(.anthropic)
        )
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

    private func sendOpenAI(
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
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": Self.openAIModel,
            "instructions": Self.directSystemPrompt,
            "input": providerTranscript(messages),
            "tools": [[
                "type": "mcp",
                "server_label": "shopware",
                "server_url": capability.url,
                "authorization": capability.token,
                "require_approval": "never"
            ]]
        ])

        let raw = try await perform(
            request,
            as: JSONValue.self,
            unauthorizedMessage: providerKeyError(.openAI)
        )
        return try await normalizedResponse(
            AIProviderResponseNormalizer.openAI(raw),
            mcpURL: mcpURL,
            approvalToken: approvalToken
        )
    }

    private func sendGemini(
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
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": Self.geminiModel,
            "system_instruction": Self.directSystemPrompt,
            "store": false,
            "input": providerTranscript(messages),
            "tools": [[
                "type": "mcp_server",
                "name": "shopware",
                "url": capability.url,
                "headers": ["Authorization": "Bearer \(capability.token)"]
            ]]
        ])

        let raw = try await perform(
            request,
            as: JSONValue.self,
            unauthorizedMessage: providerKeyError(.gemini)
        )
        return try await normalizedResponse(
            AIProviderResponseNormalizer.gemini(raw),
            mcpURL: mcpURL,
            approvalToken: approvalToken
        )
    }

    private func normalizedResponse(
        _ result: AIProviderResult,
        mcpURL: URL,
        approvalToken: String?
    ) async throws -> AIChatResponse {
        let approval = try await directApproval(
            content: result.content,
            mcpURL: mcpURL,
            previousApprovalToken: approvalToken
        )
        return AIChatResponse(
            content: result.content,
            stopReason: result.stopReason,
            usage: result.usage,
            approval: approval
        )
    }

    /// Both Responses and Interactions accept plain text input. Replaying a
    /// compact transcript keeps BYOK turns stateless and preserves the exact
    /// MCP arguments the model must retry after native approval.
    private func providerTranscript(_ messages: [AIMessage]) -> String {
        messages.map { message in
            let content = message.content.compactMap(providerTranscriptBlock).joined(separator: "\n")
            return "\(message.role.uppercased()):\n\(content)"
        }.joined(separator: "\n\n")
    }

    private func providerTranscriptBlock(_ block: AIContentBlock) -> String? {
        switch block {
        case .text(let text):
            return text
        case .toolUse(let id, let name, let input):
            return "[Tool call \(id): \(name), arguments: \(jsonString(input))]"
        case .toolResult(let id, let content, let isError):
            return "[Tool result \(id)\(isError ? " failed" : ""): \(content)]"
        case .other(let raw):
            let type = raw["type"]?.stringValue ?? "provider event"
            return "[\(type): \(jsonString(raw))]"
        }
    }

    private func jsonString(_ value: JSONValue) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
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

    private func perform<T: Decodable>(
        _ request: URLRequest,
        as type: T.Type,
        unauthorizedMessage: String? = nil
    ) async throws -> T {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            if status == 401, let unauthorizedMessage {
                throw ShopwareAPIError.message(unauthorizedMessage)
            }
            throw ShopwareAPIError.message(errorMessage(from: data, status: status))
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ShopwareAPIError.message("The AI service returned an invalid response.")
        }
    }

    private func providerKeyError(_ provider: AIProvider) -> String {
        "\(provider.displayName): \(AppLocalization.string("The AI provider rejected the API key. Check the key and its billing access."))"
    }

    private func errorMessage(from data: Data, status: Int) -> String {
        struct ErrorBody: Decodable {
            struct Inner: Decodable { let message: String }
            let error: Inner
        }
        if let body = try? JSONDecoder().decode(ErrorBody.self, from: data) { return body.error.message }
        switch status {
        case 401: return AppLocalization.string("The AI service rejected the subscription. Try restoring purchases.")
        case 413: return AppLocalization.string("This conversation is too large. Start a new chat.")
        case 429: return AppLocalization.string("Your AI usage limit was reached. Please try again later.")
        case 503: return AppLocalization.string("The AI assistant is temporarily unavailable.")
        default: return AppLocalization.string("The AI service returned an error (\(status)).")
        }
    }
}
