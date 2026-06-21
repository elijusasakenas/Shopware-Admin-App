//
//  ShopwareAdminClient.swift
//  ShopwareApp
//
//  Thin async client over the Shopware 6 Admin API: OAuth token handling,
//  search/aggregation queries, and the entity reads/writes the dashboard needs.
//

import Foundation

final class ShopwareAdminClient {
    private let connection: ShopwareConnection
    private let session: URLSession
    private var token: AccessToken?

    init(connection: ShopwareConnection, session: URLSession = .shared) {
        self.connection = connection
        self.session = session
    }

    func testConnection() async throws { _ = try await countEntity("order") }

    func dashboardMetrics(salesChannelID: String?) async throws -> DashboardMetrics {
        let todayFilter: [String: Any] = [
            "type": "range",
            "field": "orderDateTime",
            "parameters": ["gte": Calendar.current.startOfDay(for: Date()).iso8601String]
        ]
        let channelFilter: [String: Any]? = salesChannelID.map {
            ["type": "equals", "field": "salesChannelId", "value": $0]
        }
        let visibilityFilter: [String: Any]? = salesChannelID.map {
            ["type": "equals", "field": "visibilities.salesChannelId", "value": $0]
        }
        let channelFilters: [[String: Any]] = channelFilter.map { [$0] } ?? []

        let todayFilters: [[String: Any]] = [todayFilter] + channelFilters
        let openFilters: [[String: Any]] = [[
            "type": "equals", "field": "stateMachineState.technicalName", "value": "open"
        ]] + channelFilters
        let productFilters: [[String: Any]] = visibilityFilter.map { [$0] } ?? []
        let customerFilters: [[String: Any]] = channelFilters
        let latestFilters: [[String: Any]] = channelFilters

        async let orderCountToday = countEntity("order", filters: todayFilters)
        async let openOrderCount = countEntity("order", filters: openFilters)
        async let productCount = countEntity("product", filters: productFilters)
        async let customerCount = countEntity("customer", filters: customerFilters)
        async let todayOrders = searchOrders([
            "limit": 100,
            "filter": todayFilters,
            "sort": [["field": "orderDateTime", "order": "DESC"]],
            "associations": ["currency": [:]]
        ])
        async let latestOrders = searchOrders([
            "limit": 8,
            "filter": latestFilters,
            "sort": [["field": "orderDateTime", "order": "DESC"]],
            "associations": ["currency": [:], "stateMachineState": [:]]
        ])

        let resolvedToday = try await todayOrders
        let resolvedLatest = try await latestOrders
        let currency = resolvedLatest.first?.currencyCode ?? resolvedToday.first?.currencyCode ?? "EUR"

        return DashboardMetrics(
            orderCountToday: try await orderCountToday,
            openOrderCount: try await openOrderCount,
            productCount: try await productCount,
            customerCount: try await customerCount,
            todayRevenue: resolvedToday.reduce(Decimal(0)) { $0 + $1.amountTotal },
            currencyCode: currency,
            latestOrders: resolvedLatest
        )
    }

    func fetchSalesChannels() async throws -> [SalesChannel] {
        // Product comparison/feed channels (type ed535e57...) carry no orders,
        // customers, or visibilities — exclude them like the admin dashboard does
        let response = try await requestJSON(path: "/api/search/sales-channel", method: "POST", body: [
            "limit": 50,
            "filter": [
                ["type": "equals", "field": "active", "value": true],
                ["type": "not", "operator": "and", "queries": [
                    ["type": "equals", "field": "typeId", "value": "ed535e5722134ac1aa6524f73e26881b"]
                ]]
            ],
            "sort": [["field": "name", "order": "ASC"]]
        ])
        return (response["data"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            let attrs = entityAttributes(of: row)
            let name = translatedName(from: attrs) ?? attrs["name"] as? String ?? "Unnamed channel"
            let maintenance = attrs["maintenance"] as? Bool ?? false
            return SalesChannel(id: id, name: name, maintenance: maintenance)
        }
    }

    func fetchPromotions() async throws -> [Promotion] {
        let response = try await requestJSON(path: "/api/search/promotion", method: "POST", body: [
            "limit": 100,
            "sort": [["field": "createdAt", "order": "DESC"]]
        ])
        return (response["data"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            let attrs = entityAttributes(of: row)
            return Promotion(
                id: id,
                name: translatedName(from: attrs) ?? attrs["name"] as? String ?? "Unnamed promotion",
                active: attrs["active"] as? Bool ?? false,
                code: attrs["code"] as? String
            )
        }
    }

    func setPromotionActive(promotionID: String, active: Bool) async throws {
        _ = try await requestJSON(path: "/api/promotion/\(promotionID)", method: "PATCH", body: [
            "active": active
        ])
    }

    func fetchRecentCustomers() async throws -> [CustomerRegistration] {
        let response = try await requestJSON(path: "/api/search/customer", method: "POST", body: [
            "limit": 25,
            "sort": [["field": "createdAt", "order": "DESC"]]
        ])
        return (response["data"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            let attrs = entityAttributes(of: row)
            let first = attrs["firstName"] as? String ?? ""
            let last = attrs["lastName"] as? String ?? ""
            return CustomerRegistration(
                id: id,
                name: "\(first) \(last)".trimmingCharacters(in: .whitespaces),
                email: attrs["email"] as? String ?? "Unknown",
                createdAt: date(from: attrs["createdAt"] as? String),
                guest: attrs["guest"] as? Bool ?? false
            )
        }
    }

    func fetchLogEntries() async throws -> [LogEntry] {
        let response = try await requestJSON(path: "/api/search/log-entry", method: "POST", body: [
            "limit": 25,
            "sort": [["field": "createdAt", "order": "DESC"]]
        ])
        return (response["data"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            let attrs = entityAttributes(of: row)
            return LogEntry(
                id: id,
                message: attrs["message"] as? String ?? "No message",
                level: attrs["level"] as? Int ?? 200,
                createdAt: date(from: attrs["createdAt"] as? String)
            )
        }
    }

    func fetchDomainURLs() async throws -> [String] {
        let response = try await requestJSON(path: "/api/search/sales-channel-domain", method: "POST", body: [
            "limit": 10
        ])
        return (response["data"] as? [[String: Any]] ?? []).compactMap { row in
            entityAttributes(of: row)["url"] as? String
        }
    }

    func fetchShopwareVersion() async throws -> String {
        let response = try await requestJSON(path: "/api/_info/version", method: "GET")
        return response["version"] as? String ?? "Unknown"
    }

    func fetchNewsletterRecipients() async throws -> [NewsletterRecipient] {
        let response = try await requestJSON(path: "/api/search/newsletter-recipient", method: "POST", body: [
            "limit": 100,
            "sort": [["field": "createdAt", "order": "DESC"]]
        ])
        return (response["data"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            let attrs = entityAttributes(of: row)
            return NewsletterRecipient(
                id: id,
                email: attrs["email"] as? String ?? "Unknown",
                status: attrs["status"] as? String ?? "notSet",
                createdAt: date(from: attrs["createdAt"] as? String)
            )
        }
    }

    func setMaintenance(salesChannelID: String, enabled: Bool) async throws {
        _ = try await requestJSON(path: "/api/sales-channel/\(salesChannelID)", method: "PATCH", body: [
            "maintenance": enabled
        ])
    }

    func fetchOrderLineItems(orderID: String) async throws -> [OrderLineItem] {
        let response = try await requestJSON(path: "/api/search/order-line-item", method: "POST", body: [
            "limit": 100,
            "filter": [["type": "equals", "field": "orderId", "value": orderID]],
            "sort": [["field": "position", "order": "ASC"]]
        ])
        return (response["data"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            let attrs = entityAttributes(of: row)
            return OrderLineItem(
                id: id,
                label: attrs["label"] as? String ?? "Item",
                quantity: attrs["quantity"] as? Int ?? 0,
                totalPrice: decimal(from: attrs["totalPrice"])
            )
        }
    }

    func fetchOrderCustomer(orderID: String) async throws -> (name: String, email: String)? {
        let response = try await requestJSON(path: "/api/search/order-customer", method: "POST", body: [
            "limit": 1,
            "filter": [["type": "equals", "field": "orderId", "value": orderID]]
        ])
        guard let row = (response["data"] as? [[String: Any]])?.first else { return nil }
        let attrs = entityAttributes(of: row)
        let first = attrs["firstName"] as? String ?? ""
        let last = attrs["lastName"] as? String ?? ""
        return (name: "\(first) \(last)".trimmingCharacters(in: .whitespaces),
                email: attrs["email"] as? String ?? "")
    }

    // entityName: "order", "order_transaction" or "order_delivery"
    func fetchStateTransitions(entityName: String, entityID: String) async throws -> [OrderTransition] {
        let response = try await requestJSON(path: "/api/_action/state-machine/\(entityName)/\(entityID)/state", method: "GET")
        return (response["transitions"] as? [[String: Any]] ?? []).compactMap { transition in
            guard let action = transition["actionName"] as? String else { return nil }
            // Carry the destination state's language-neutral technicalName so the
            // app localizes the menu label itself (falls back to the action name).
            let toState = transition["toStateMachineState"] as? [String: Any]
            let targetTechnicalName = toState?["technicalName"] as? String ?? action
            return OrderTransition(actionName: action, targetStateTechnicalName: targetTechnicalName)
        }
    }

    func performStateTransition(entityName: String, entityID: String, action: String) async throws {
        _ = try await requestJSON(path: "/api/_action/state-machine/\(entityName)/\(entityID)/state/\(action)", method: "POST")
    }

    // Returns the newest transaction/delivery of an order with its current state name
    func fetchOrderSubEntity(_ entity: String, orderID: String) async throws -> (id: String, state: String)? {
        let response = try await requestJSON(path: "/api/search/\(entity)", method: "POST", body: [
            "limit": 1,
            "filter": [["type": "equals", "field": "orderId", "value": orderID]],
            "sort": [["field": "createdAt", "order": "DESC"]],
            "associations": ["stateMachineState": [:]]
        ])
        guard let row = (response["data"] as? [[String: Any]])?.first,
              let id = row["id"] as? String else { return nil }
        let attrs = entityAttributes(of: row)
        let included = response["included"] as? [[String: Any]] ?? []
        let includedByID = Dictionary(uniqueKeysWithValues: included.compactMap { item -> (String, [String: Any])? in
            guard let itemID = item["id"] as? String else { return nil }
            return (itemID, item)
        })
        let relationships = row["relationships"] as? [String: Any] ?? [:]
        let stateID = relationshipID(from: relationships["stateMachineState"])
        let stateAttrs = includedByID[stateID ?? ""]?["attributes"] as? [String: Any]
        return (id: id, state: orderStateTechnicalName(from: attrs, includedState: stateAttrs))
    }

    func fetchLowStockProducts(threshold: Int = 10, salesChannelID: String?) async throws -> [LowStockProduct] {
        var filters: [[String: Any]] = [
            ["type": "range", "field": "stock", "parameters": ["lte": threshold]],
            ["type": "equals", "field": "active", "value": true]
        ]
        if let salesChannelID {
            filters.append(["type": "equals", "field": "visibilities.salesChannelId", "value": salesChannelID])
        }
        let response = try await requestJSON(path: "/api/search/product", method: "POST", body: [
            "limit": 10,
            "filter": filters,
            "sort": [["field": "stock", "order": "ASC"]]
        ])
        return (response["data"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            let attrs = entityAttributes(of: row)
            let name = translatedName(from: attrs) ?? attrs["name"] as? String ?? "Unnamed product"
            return LowStockProduct(id: id, name: name, stock: attrs["stock"] as? Int ?? 0)
        }
    }

    func fetchLanguageBreakdown(since: Date, salesChannelID: String?) async throws -> [LanguageStat] {
        var filters: [[String: Any]] = [[
            "type": "range",
            "field": "orderDateTime",
            "parameters": ["gte": since.iso8601String]
        ]]
        if let salesChannelID {
            filters.append(["type": "equals", "field": "salesChannelId", "value": salesChannelID])
        }

        let response = try await requestJSON(path: "/api/search/order", method: "POST", body: [
            "limit": 1,
            "includes": ["order": ["id"]],
            "filter": filters,
            "aggregations": [[
                "name": "languages",
                "type": "terms",
                "field": "languageId",
                "aggregation": ["name": "amount_sum", "type": "sum", "field": "amountTotal"]
            ]]
        ])

        guard let aggregations = response["aggregations"] as? [String: Any],
              let terms = aggregations["languages"] as? [String: Any],
              let buckets = terms["buckets"] as? [[String: Any]], !buckets.isEmpty else {
            return []
        }

        let languageNames = (try? await fetchLanguageNames()) ?? [:]

        return buckets.compactMap { bucket -> LanguageStat? in
            guard let languageID = bucket["key"] as? String else { return nil }
            let count = bucket["count"] as? Int ?? 0
            let amount = ((bucket["amount_sum"] as? [String: Any])?["sum"] as? NSNumber)?.doubleValue ?? 0
            return LanguageStat(
                id: languageID,
                name: languageNames[languageID] ?? "Unknown language",
                count: count,
                amount: amount
            )
        }
        .sorted { $0.count > $1.count }
    }

    private func fetchLanguageNames() async throws -> [String: String] {
        let response = try await requestJSON(path: "/api/search/language", method: "POST", body: ["limit": 50])
        var names: [String: String] = [:]
        for row in (response["data"] as? [[String: Any]] ?? []) {
            guard let id = row["id"] as? String else { continue }
            let attrs = entityAttributes(of: row)
            names[id] = attrs["name"] as? String ?? "Unknown language"
        }
        return names
    }

    func fetchTopProducts(since: Date, salesChannelID: String?) async throws -> [TopProduct] {
        var filters: [[String: Any]] = [
            ["type": "range", "field": "order.orderDateTime", "parameters": ["gte": since.iso8601String]],
            ["type": "equals", "field": "type", "value": "product"]
        ]
        if let salesChannelID {
            filters.append(["type": "equals", "field": "order.salesChannelId", "value": salesChannelID])
        }
        let response = try await requestJSON(path: "/api/search/order-line-item", method: "POST", body: [
            "limit": 1,
            "includes": ["order_line_item": ["id"]],
            "filter": filters,
            "aggregations": [[
                "name": "top_products",
                "type": "terms",
                "field": "label",
                "limit": 50,
                "aggregation": ["name": "qty", "type": "sum", "field": "quantity"]
            ]]
        ])
        guard let aggregations = response["aggregations"] as? [String: Any],
              let terms = aggregations["top_products"] as? [String: Any],
              let buckets = terms["buckets"] as? [[String: Any]] else {
            return []
        }
        return buckets.compactMap { bucket -> TopProduct? in
            guard let label = bucket["key"] as? String else { return nil }
            let qty = ((bucket["qty"] as? [String: Any])?["sum"] as? NSNumber)?.intValue ?? bucket["count"] as? Int ?? 0
            return TopProduct(label: label, quantitySold: qty)
        }
        .sorted { $0.quantitySold > $1.quantitySold }
        .prefix(5)
        .map { $0 }
    }

    // Uses a histogram aggregation on the order search instead of the
    // /_admin/dashboard endpoint, because that endpoint cannot filter by sales channel.
    func fetchHistory(paid: Bool, range: DateRange, salesChannelID: String?) async throws -> [DashboardBucket] {
        var filters: [[String: Any]] = [[
            "type": "range",
            "field": "orderDateTime",
            "parameters": ["gte": range.sinceDate.iso8601String]
        ]]
        if let salesChannelID {
            filters.append(["type": "equals", "field": "salesChannelId", "value": salesChannelID])
        }
        if paid {
            filters.append(["type": "equals", "field": "transactions.stateMachineState.technicalName", "value": "paid"])
        }

        let response = try await requestJSON(path: "/api/search/order", method: "POST", body: [
            "limit": 1,
            "includes": ["order": ["id"]],
            "filter": filters,
            "aggregations": [[
                "name": "order_histogram",
                "type": "histogram",
                "field": "orderDateTime",
                "interval": range.histogramInterval,
                "aggregation": ["name": "amount_sum", "type": "sum", "field": "amountTotal"]
            ]]
        ])

        guard let aggregations = response["aggregations"] as? [String: Any],
              let histogram = aggregations["order_histogram"] as? [String: Any],
              let buckets = histogram["buckets"] as? [[String: Any]] else {
            return []
        }

        return buckets.compactMap { bucket -> DashboardBucket? in
            guard let key = bucket["key"] as? String, let date = parseHistogramDate(key) else { return nil }
            let count = bucket["count"] as? Int ?? 0
            let amount = ((bucket["amount_sum"] as? [String: Any])?["sum"] as? NSNumber)?.doubleValue ?? 0
            return DashboardBucket(date: date, count: count, amount: amount)
        }
        .sorted { $0.date < $1.date }
    }

    private func countEntity(_ entity: String, filters: [[String: Any]] = []) async throws -> Int {
        let response = try await searchEntity(entity, body: ["limit": 1, "filter": filters, "total-count-mode": 1])
        if let meta = response["meta"] as? [String: Any], let total = meta["total"] as? Int { return total }
        if let total = response["total"] as? Int { return total }
        return (response["data"] as? [[String: Any]])?.count ?? 0
    }

    private func searchOrders(_ body: [String: Any]) async throws -> [LatestOrder] {
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

    private func searchEntity(_ entity: String, body: [String: Any]) async throws -> [String: Any] {
        try await requestJSON(path: "/api/search/\(entity)", method: "POST", body: body)
    }

    private func requestJSON(path: String, method: String, body: [String: Any]? = nil, queryItems: [URLQueryItem]? = nil, attempt: Int = 0) async throws -> [String: Any] {
        let accessToken = try await accessToken()
        var url = connection.normalizedBaseURL.appending(path: path)
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
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if status == 401 && attempt == 0 {
            token = nil
            return try await requestJSON(path: path, method: method, body: body, queryItems: queryItems, attempt: 1)
        }

        if [408, 429, 500, 502, 503, 504].contains(status), attempt < 2 {
            try await Task.sleep(for: .milliseconds(500 * (attempt + 1)))
            return try await requestJSON(path: path, method: method, body: body, queryItems: queryItems, attempt: attempt + 1)
        }

        return try parseJSONResponse(data: data, status: status)
    }

    private func accessToken() async throws -> String {
        if let token, token.expiresAt > Date().addingTimeInterval(30) { return token.value }

        var request = URLRequest(url: connection.normalizedBaseURL.appending(path: "/api/oauth/token"))
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
        token = AccessToken(value: value, expiresAt: Date().addingTimeInterval(expiresIn))
        return value
    }

    private func parseJSONResponse(data: Data, status: Int) throws -> [String: Any] {
        let payload: Any = data.isEmpty ? [:] : (try JSONSerialization.jsonObject(with: data))
        if !(200...299).contains(status) {
            throw ShopwareAPIError.message(errorMessage(from: payload, status: status))
        }
        return payload as? [String: Any] ?? [:]
    }
}
