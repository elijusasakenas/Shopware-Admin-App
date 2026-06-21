//
//  Charts.swift
//  ShopwareApp
//
//  Swift Charts views for the dashboard: the range-selectable card wrapper,
//  the orders/turnover area charts, the sales-by-language breakdown, and the
//  DateRange model that drives all of them.
//

import Charts
import SwiftUI

// MARK: - Chart card wrapper

struct ChartCard<ChartContent: View>: View {
    let title: LocalizedStringKey
    let ranges: [DateRange]
    @Binding var selectedRange: DateRange
    let isLoading: Bool
    let onRangeChange: () -> Void
    @ViewBuilder let chartContent: () -> ChartContent

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.primaryText)
                    Text(selectedRange.subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.secondaryText)
                }
                Spacer()
                if isLoading {
                    ProgressView().scaleEffect(0.7)
                }
                Menu {
                    ForEach(ranges, id: \.self) { range in
                        Button {
                            selectedRange = range
                            onRangeChange()
                        } label: {
                            if selectedRange == range {
                                Label(range.menuLabel, systemImage: "checkmark")
                            } else {
                                Text(range.menuLabel)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(selectedRange.menuLabel)
                            .font(.subheadline)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(Color.primaryText)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            chartContent()
                .frame(height: 190)
        }
        .padding(20)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.border.opacity(0.7), lineWidth: 1))
    }
}

// MARK: - Charts

struct OrdersBarChart: View {
    let buckets: [DashboardBucket]
    let range: DateRange

    var body: some View {
        if buckets.isEmpty {
            ChartEmptyState(text: "No orders in this period")
        } else {
            Chart(buckets) { bucket in
                AreaMark(
                    x: .value("Date", bucket.date, unit: range.calendarComponent),
                    y: .value("Orders", bucket.count)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.shopwareBlue.opacity(0.16), Color.shopwareBlue.opacity(0.01)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Date", bucket.date, unit: range.calendarComponent),
                    y: .value("Orders", bucket.count)
                )
                .foregroundStyle(Color.shopwareBlue)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisValueLabel(format: range.axisFormat)
                        .foregroundStyle(Color.secondaryText)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Color.border.opacity(0.55))
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("\(v)").foregroundStyle(Color.secondaryText)
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.45), value: buckets.map(\.count))
        }
    }
}

struct RevenueBarChart: View {
    let buckets: [DashboardBucket]
    let range: DateRange
    let currency: String

    var body: some View {
        if buckets.isEmpty {
            ChartEmptyState(text: "No turnover in this period")
        } else {
            Chart(buckets) { bucket in
                AreaMark(
                    x: .value("Date", bucket.date, unit: range.calendarComponent),
                    y: .value("Turnover", bucket.amount)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.shopwareBlue.opacity(0.16), Color.shopwareBlue.opacity(0.01)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Date", bucket.date, unit: range.calendarComponent),
                    y: .value("Turnover", bucket.amount)
                )
                .foregroundStyle(Color.shopwareBlue)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisValueLabel(format: range.axisFormat)
                        .foregroundStyle(Color.secondaryText)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Color.border.opacity(0.55))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(v.formatted(.currency(code: currency).precision(.fractionLength(2))))
                                .font(.caption2)
                                .foregroundStyle(Color.secondaryText)
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.45), value: buckets.map(\.amount))
        }
    }
}

struct LanguageBreakdownCard: View {
    let stats: [LanguageStat]
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Sales by language")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.primaryText)
                Text("Last 30 days · where your customers buy")
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText)
            }

            let maxCount = max(stats.map(\.count).max() ?? 1, 1)

            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 10) {
                        Text(stat.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primaryText)
                            .lineLimit(1)
                        Spacer()
                        Text(stat.count == 1 ? "1 order" : "\(stat.count) orders")
                            .font(.caption)
                            .foregroundStyle(Color.secondaryText)
                        Text(stat.amount.formatted(.currency(code: currency).precision(.fractionLength(0))))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.primaryText)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.border.opacity(0.4))
                            Capsule()
                                .fill(Color.shopwareBlue)
                                .frame(width: max(geo.size.width * CGFloat(stat.count) / CGFloat(maxCount), 6))
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.border.opacity(0.7), lineWidth: 1))
    }
}

struct ChartEmptyState: View {
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.title2)
                .foregroundStyle(Color.border)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Date ranges

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
