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
    var todayOrders: [LatestOrder] = []
}

enum TrendComparison {
    static func halfOverHalfPercent(_ values: [Double]) -> Double? {
        guard values.count >= 2 else { return nil }
        let mid = values.count / 2
        let previous = values.prefix(mid).reduce(0, +)
        let current = values.suffix(values.count - mid).reduce(0, +)
        guard previous > 0 else { return nil }
        return ((current - previous) / previous) * 100
    }

    static func dayOverDayPercent(buckets: [DashboardBucket], now: Date = Date(), calendar: Calendar = .current) -> Double? {
        let today = calendar.startOfDay(for: now)
        guard let todayAmount = buckets.first(where: { calendar.isDate($0.date, inSameDayAs: today) })?.amount,
              let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let previousAmount = buckets.first(where: { calendar.isDate($0.date, inSameDayAs: yesterday) })?.amount,
              previousAmount > 0
        else { return nil }
        return ((todayAmount - previousAmount) / previousAmount) * 100
    }
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
