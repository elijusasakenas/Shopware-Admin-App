import Charts
import SwiftUI

struct HeroSparkline: View {
    let buckets: [DashboardBucket]

    var body: some View {
        if buckets.isEmpty {
            Rectangle()
                .fill(Color.border)
                .frame(height: 1)
        } else {
            Chart(buckets.suffix(7)) { bucket in
                AreaMark(
                    x: .value("Date", bucket.date),
                    y: .value("Turnover", bucket.amount)
                )
                .foregroundStyle(Color.shopwareBlue.opacity(0.10))
                .interpolationMethod(.monotone)
                LineMark(
                    x: .value("Date", bucket.date),
                    y: .value("Turnover", bucket.amount)
                )
                .foregroundStyle(Color.shopwareBlue)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
        }
    }
}

struct IndustryTrendChart: View {
    let buckets: [DashboardBucket]
    let metric: TrendMetric
    let range: DateRange
    let currency: String

    private var values: [Double] {
        buckets.map { bucket in
            switch metric {
            case .orders: return Double(bucket.count)
            case .turnover: return bucket.amount
            case .basket: return bucket.count == 0 ? 0 : bucket.amount / Double(bucket.count)
            }
        }
    }

    var body: some View {
        if buckets.isEmpty {
            Text("No data in this period")
                .font(.subheadline)
                .foregroundStyle(Color.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart(Array(zip(buckets, values)), id: \.0.id) { bucket, value in
                AreaMark(
                    x: .value("Date", bucket.date, unit: range.calendarComponent),
                    y: .value(metric.label, value)
                )
                .foregroundStyle(Color.shopwareBlue.opacity(0.10))
                .interpolationMethod(.monotone)
                LineMark(
                    x: .value("Date", bucket.date, unit: range.calendarComponent),
                    y: .value(metric.label, value)
                )
                .foregroundStyle(Color.shopwareBlue)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: range.axisFormat)
                        .font(.caption2)
                        .foregroundStyle(Color.secondaryText)
                    AxisTick().foregroundStyle(Color.clear)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Color.border.opacity(0.6))
                    AxisTick().foregroundStyle(Color.clear)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(axisLabel(number))
                                .font(.caption2)
                                .foregroundStyle(Color.secondaryText)
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.35), value: values)
        }
    }

    private func axisLabel(_ value: Double) -> String {
        switch metric {
        case .orders:
            return Int(value).formatted()
        case .turnover, .basket:
            return value.formatted(.currency(code: currency).precision(.fractionLength(0)))
        }
    }
}

struct TickBar: View {
    let fraction: Double

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<20, id: \.self) { index in
                Capsule()
                    .fill(Double(index) < fraction * 20 ? Color.shopwareBlue : Color.border.opacity(0.7))
                    .frame(height: 5)
            }
        }
    }
}
