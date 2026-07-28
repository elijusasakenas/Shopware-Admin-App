//
//  ShopwareAdminClient+Dashboard.swift
//  ShopwareApp
//
//  Dashboard KPIs, charts, top products, and sales-channel listing.
//

import Foundation

extension ShopwareAdminClient {
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
            let name = translatedName(from: attrs) ?? attrs["name"] as? String ?? String(localized: "Unnamed product")
            return LowStockProduct(
                id: id,
                name: name,
                productNumber: attrs["productNumber"] as? String ?? "",
                stock: attrs["stock"] as? Int ?? 0
            )
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
}
