//
//  Date+Shopware.swift
//  ShopwareApp
//
//  ISO 8601 formatters and helpers matching Shopware's date encoding.
//

import Foundation

extension Date {
    var iso8601String: String { ISO8601DateFormatter.shopware.string(from: self) }
}

extension ISO8601DateFormatter {
    static let shopware: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let shopwareDate: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return f
    }()
}
