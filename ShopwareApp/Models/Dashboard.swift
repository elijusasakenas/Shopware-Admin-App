//
//  Dashboard.swift
//  ShopwareApp
//
//  Aggregated dashboard metrics and the time-series bucket used by the charts.
//

import Foundation

struct DashboardMetrics {
    var orderCountToday: Int
    var openOrderCount: Int
    var productCount: Int
    var customerCount: Int
    var todayRevenue: Decimal
    var currencyCode: String
    var latestOrders: [LatestOrder]
}

struct DashboardBucket: Identifiable {
    var id: String { ISO8601DateFormatter.shopware.string(from: date) }
    var date: Date
    var count: Int
    var amount: Double
}

enum TrendMetric: String, CaseIterable, Identifiable {
    case orders
    case turnover
    case basket

    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

struct AttentionItem: Identifiable {
    enum Destination {
        case order(LatestOrder)
        case products
        case resolve
    }

    var id: String
    var severity: Int
    var title: String
    var meta: String
    var action: String
    var destination: Destination
}
