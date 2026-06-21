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
