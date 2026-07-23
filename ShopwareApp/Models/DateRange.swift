//
//  DateRange.swift
//  ShopwareApp
//
//  Chart / history window model shared by the dashboard UI and Admin API
//  histogram queries.
//

import Foundation
import SwiftUI

enum DateRange: String, CaseIterable {
    case days30 = "30Days"
    case days14 = "14Days"
    case days7  = "7Days"
    case hours24 = "24Hours"
    case yesterday = "Yesterday"

    var menuLabel: LocalizedStringKey {
        switch self {
        case .days30:    return "Last 30 days"
        case .days14:    return "Last 14 days"
        case .days7:     return "Last 7 days"
        case .hours24:   return "Last 24 hours"
        case .yesterday: return "Yesterday"
        }
    }

    // "13 May - 12 Jun" under the card title, like the admin dashboard
    var subtitle: String {
        let format = Date.FormatStyle().day().month(.abbreviated)
        if self == .yesterday {
            return sinceDate.formatted(format)
        }
        return "\(sinceDate.formatted(format)) - \(Date().formatted(format))"
    }

    var sinceDate: Date {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .days30:
            return cal.startOfDay(for: cal.date(byAdding: .day, value: -30, to: now)!)
        case .days14:
            return cal.startOfDay(for: cal.date(byAdding: .day, value: -14, to: now)!)
        case .days7:
            return cal.startOfDay(for: cal.date(byAdding: .day, value: -7, to: now)!)
        case .hours24:
            return cal.date(byAdding: .hour, value: -24, to: now)!
        case .yesterday:
            return cal.startOfDay(for: cal.date(byAdding: .day, value: -1, to: now)!)
        }
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .hours24, .yesterday: return .hour
        default:                   return .day
        }
    }

    var histogramInterval: String {
        switch self {
        case .hours24, .yesterday: return "hour"
        default:                   return "day"
        }
    }

    var axisFormat: Date.FormatStyle {
        switch self {
        case .hours24, .yesterday: return .dateTime.hour()
        default:                   return .dateTime.month(.abbreviated).day()
        }
    }
}
