//
//  AIUsage.swift
//  ShopwareApp
//
//  Device-local, month-scoped AI usage counter. Every model round trip
//  records its token usage; the settings screen shows the running totals.
//  Counters reset automatically when a new month starts.
//

import Foundation

enum AIUsage {
    struct Snapshot {
        let requests: Int
        let inputTokens: Int
        let outputTokens: Int
    }

    private static let monthKey = "ai.usage.month"
    private static let requestsKey = "ai.usage.requests"
    private static let inputKey = "ai.usage.inputTokens"
    private static let outputKey = "ai.usage.outputTokens"

    static func record(inputTokens: Int, outputTokens: Int, defaults: UserDefaults = .standard) {
        resetIfNewMonth(defaults)
        defaults.set(defaults.integer(forKey: requestsKey) + 1, forKey: requestsKey)
        defaults.set(defaults.integer(forKey: inputKey) + inputTokens, forKey: inputKey)
        defaults.set(defaults.integer(forKey: outputKey) + outputTokens, forKey: outputKey)
    }

    static func snapshot(defaults: UserDefaults = .standard) -> Snapshot {
        resetIfNewMonth(defaults)
        return Snapshot(
            requests: defaults.integer(forKey: requestsKey),
            inputTokens: defaults.integer(forKey: inputKey),
            outputTokens: defaults.integer(forKey: outputKey)
        )
    }

    private static func currentMonth() -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: Date())
        return "\(components.year ?? 0)-\(components.month ?? 0)"
    }

    private static func resetIfNewMonth(_ defaults: UserDefaults) {
        let month = currentMonth()
        guard defaults.string(forKey: monthKey) != month else { return }
        defaults.set(month, forKey: monthKey)
        defaults.set(0, forKey: requestsKey)
        defaults.set(0, forKey: inputKey)
        defaults.set(0, forKey: outputKey)
    }
}
