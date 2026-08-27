//
//  ShopwareAdminClient+MCP.swift
//  ShopwareApp
//
//  Shopware built-in MCP server probe for the AI assistant (6.7.11+).
//

import Foundation

extension ShopwareAdminClient {
    /// The shop's built-in MCP endpoint, used by the AI assistant.
    func mcpEndpointURL() throws -> URL {
        try connection.resolvedBaseURL().appending(path: "/api/_mcp")
    }

    /// A valid Admin API bearer token (cached until shortly before expiry).
    /// The AI proxy forwards it so the model can call the shop's MCP server.
    func currentAccessToken() async throws -> String {
        try await accessToken()
    }

    enum MCPAvailability: Equatable {
        case available
        /// The shop runs a Shopware version older than the MCP server.
        case unsupportedVersion(current: String, required: String)
        /// The version is new enough but the MCP_SERVER feature flag is off.
        case disabled
        case failed(String)
    }

    /// Checks whether the shop exposes the MCP server the AI assistant needs.
    /// The endpoint only exists on Shopware >= 6.7.11.0 with MCP_SERVER=1.
    func mcpAvailability() async -> MCPAvailability {
        let requiredVersion = "6.7.11.0"
        do {
            let endpoint = try mcpEndpointURL()
            guard endpoint.scheme == "https" else {
                return .failed("The AI assistant requires a Shopware connection secured with HTTPS.")
            }
            let accessToken = try await accessToken()
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": [
                    "protocolVersion": "2025-06-18",
                    "capabilities": [:],
                    "clientInfo": ["name": "ShopwareApp", "version": "1.0"]
                ]
            ])

            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            #if DEBUG
            print("MCP availability check: status=\(status) body=\(body.prefix(500))")
            #endif

            if (200...299).contains(status) {
                guard data.count <= 256_000 else {
                    return .failed("The shop's MCP endpoint returned an unexpectedly large response.")
                }
                guard body.contains("\"jsonrpc\"") && body.contains("\"result\"") else {
                    return .failed("The shop did not return a valid MCP initialize response.")
                }
                return .available
            }

            if status == 401 || status == 403 {
                return .failed("The shop rejected MCP access (HTTP \(status)). Check the integration's Admin API privileges.")
            }
            if status != 404 {
                return .failed("The shop's MCP endpoint returned HTTP \(status): \(body.prefix(300))")
            }

            // A real "flag off" 404 is Symfony's routing error. Any other 404
            // body (e.g. an MCP session error) means the endpoint exists but
            // misbehaves — surface it instead of blaming the feature flag.
            let isRouteMissing = body.contains("No route found") || body.contains("\"404\"")
            if !isRouteMissing {
                return .failed("The shop's MCP endpoint returned 404: \(body.prefix(300))")
            }

            let version = (try? await fetchShopwareVersion()) ?? "unknown"
            if isVersion(version, olderThan: requiredVersion) {
                return .unsupportedVersion(current: version, required: requiredVersion)
            }
            return .disabled
        } catch {
            return .failed(error.shopwareDisplayMessage)
        }
    }

    /// Numeric component-wise version comparison ("6.7.10.2" < "6.7.11.0").
    private func isVersion(_ version: String, olderThan required: String) -> Bool {
        // Strip suffixes like "-RC1" before comparing numerically.
        let lhs = version.split(separator: "-").first.map(String.init) ?? version
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = required.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a < b }
        }
        return false
    }
}
