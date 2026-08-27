//
//  ShopwareAdminClient.swift
//  ShopwareApp
//
//  Thin async client over the Shopware 6 Admin API: OAuth, transport, and
//  shared search helpers. Domain methods live in ShopwareAdminClient+*.swift.
//

import Foundation

final class ShopwareAdminClient {
    let connection: ShopwareConnection
    let session: URLSession

    private let tokenLock = NSLock()
    private var cachedToken: AccessToken?
    private var refreshTask: Task<AccessToken, Error>?
    private var refreshGeneration = 0

    /// Testing seam for a cached OAuth token. Production callers use `accessToken()`.
    var token: AccessToken? {
        get {
            tokenLock.lock()
            defer { tokenLock.unlock() }
            return cachedToken
        }
        set {
            tokenLock.lock()
            cachedToken = newValue
            tokenLock.unlock()
        }
    }

    init(connection: ShopwareConnection, session: URLSession = .shared) {
        self.connection = connection
        self.session = session
    }

    func testConnection() async throws { _ = try await countEntity("order") }

    func countEntity(_ entity: String, filters: [[String: Any]] = []) async throws -> Int {
        let response = try await searchEntity(entity, body: ["limit": 1, "filter": filters, "total-count-mode": 1])
        if let meta = response["meta"] as? [String: Any], let total = meta["total"] as? Int { return total }
        if let total = response["total"] as? Int { return total }
        return (response["data"] as? [[String: Any]])?.count ?? 0
    }

    func searchOrders(_ body: [String: Any]) async throws -> [LatestOrder] {
        let response = try await searchEntity("order", body: body)
        let included = response["included"] as? [[String: Any]] ?? []
        let includedByID = Dictionary(uniqueKeysWithValues: included.compactMap { item -> (String, [String: Any])? in
            guard let id = item["id"] as? String else { return nil }
            return (id, item)
        })
        return (response["data"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            let attributes = entityAttributes(of: row)
            let relationships = row["relationships"] as? [String: Any] ?? [:]
            let currencyID = relationshipID(from: relationships["currency"])
            let stateID = relationshipID(from: relationships["stateMachineState"])
            let currencyAttributes = includedByID[currencyID ?? ""]?["attributes"] as? [String: Any]
            let stateAttributes = includedByID[stateID ?? ""]?["attributes"] as? [String: Any]
            return LatestOrder(
                id: id,
                orderNumber: attributes["orderNumber"] as? String ?? "Unknown",
                amountTotal: decimal(from: attributes["amountTotal"]),
                orderDateTime: date(from: attributes["orderDateTime"] as? String),
                currencyCode: (attributes["currency"] as? [String: Any])?["isoCode"] as? String ?? currencyAttributes?["isoCode"] as? String ?? "EUR",
                state: orderStateTechnicalName(from: attributes, includedState: stateAttributes)
            )
        }
    }

    func searchEntity(_ entity: String, body: [String: Any]) async throws -> [String: Any] {
        try await requestJSON(path: "/api/search/\(entity)", method: "POST", body: body)
    }

    /// `languageID`, when set, is sent as the Shopware `sw-language-id` header so
    /// translatable fields are read/written in that language.
    func requestJSON(path: String, method: String, body: [String: Any]? = nil, queryItems: [URLQueryItem]? = nil, languageID: String? = nil, attempt: Int = 0, renewToken: Bool = false) async throws -> [String: Any] {
        let accessToken = try await accessToken(forceRefresh: renewToken)
        var url = try connection.resolvedBaseURL().appending(path: path)
        if let queryItems,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = queryItems
            url = components.url ?? url
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let languageID { request.setValue(languageID, forHTTPHeaderField: "sw-language-id") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if status == 401 && attempt == 0 {
            invalidateCachedToken()
            return try await requestJSON(
                path: path,
                method: method,
                body: body,
                queryItems: queryItems,
                languageID: languageID,
                attempt: 1,
                renewToken: true
            )
        }

        if [408, 429, 500, 502, 503, 504].contains(status), attempt < 2 {
            try await Task.sleep(for: .milliseconds(500 * (attempt + 1)))
            return try await requestJSON(path: path, method: method, body: body, queryItems: queryItems, languageID: languageID, attempt: attempt + 1)
        }

        return try parseJSONResponse(data: data, status: status)
    }

    /// Like `requestJSON` but sends a raw body (e.g. image bytes) with a custom
    /// content type. Used for the media upload action.
    @discardableResult
    func requestRaw(path: String, method: String, body: Data, contentType: String, queryItems: [URLQueryItem]? = nil, attempt: Int = 0, renewToken: Bool = false) async throws -> [String: Any] {
        let accessToken = try await accessToken(forceRefresh: renewToken)
        var url = try connection.resolvedBaseURL().appending(path: path)
        if let queryItems,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = queryItems
            url = components.url ?? url
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if status == 401 && attempt == 0 {
            invalidateCachedToken()
            return try await requestRaw(
                path: path,
                method: method,
                body: body,
                contentType: contentType,
                queryItems: queryItems,
                attempt: 1,
                renewToken: true
            )
        }

        if [408, 429, 500, 502, 503, 504].contains(status), attempt < 2 {
            try await Task.sleep(for: .milliseconds(500 * (attempt + 1)))
            return try await requestRaw(path: path, method: method, body: body, contentType: contentType, queryItems: queryItems, attempt: attempt + 1)
        }

        return try parseJSONResponse(data: data, status: status)
    }

    func accessToken(forceRefresh: Bool = false) async throws -> String {
        if forceRefresh {
            invalidateCachedToken()
        }

        tokenLock.lock()
        if let cachedToken, cachedToken.expiresAt > Date().addingTimeInterval(30) {
            let value = cachedToken.value
            tokenLock.unlock()
            return value
        }
        if let refreshTask {
            tokenLock.unlock()
            return try await refreshTask.value.value
        }
        refreshGeneration += 1
        let generation = refreshGeneration
        let task = Task { try await self.fetchAccessTokenFromNetwork() }
        refreshTask = task
        tokenLock.unlock()

        do {
            let next = try await task.value
            tokenLock.lock()
            if refreshGeneration == generation {
                cachedToken = next
                refreshTask = nil
            }
            tokenLock.unlock()
            return next.value
        } catch {
            tokenLock.lock()
            if refreshGeneration == generation {
                refreshTask = nil
            }
            tokenLock.unlock()
            throw error
        }
    }

    private func invalidateCachedToken() {
        tokenLock.lock()
        cachedToken = nil
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        tokenLock.unlock()
    }

    private func fetchAccessTokenFromNetwork() async throws -> AccessToken {
        var request = URLRequest(url: try connection.resolvedBaseURL().appending(path: "/api/oauth/token"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "client_credentials",
            "client_id": connection.accessKey.trimmingCharacters(in: .whitespacesAndNewlines),
            "client_secret": connection.secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        ])

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try parseJSONResponse(data: data, status: status)

        guard let value = json["access_token"] as? String else {
            throw ShopwareAPIError.message("Shopware did not return an access token.")
        }

        let expiresIn = json["expires_in"] as? TimeInterval ?? 600
        return AccessToken(value: value, expiresAt: Date().addingTimeInterval(expiresIn))
    }

    func parseJSONResponse(data: Data, status: Int) throws -> [String: Any] {
        let payload: Any = data.isEmpty ? [:] : (try JSONSerialization.jsonObject(with: data))
        if !(200...299).contains(status) {
            throw ShopwareAPIError.message(errorMessage(from: payload, status: status))
        }
        return payload as? [String: Any] ?? [:]
    }
}
