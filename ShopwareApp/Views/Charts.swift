import Charts
import SwiftUI

struct HeroSparkline: View {
    let buckets: [DashboardBucket]

    var body: some View {
        if buckets.isEmpty {
            Rectangle()
                .fill(Color.industryHair)
                .frame(height: 1)
        } else {
            Chart(buckets.suffix(7)) { bucket in
                AreaMark(
                    x: .value("Date", bucket.date),
                    y: .value("Turnover", bucket.amount)
                )
                .foregroundStyle(Color.industryAccentTint)
                .interpolationMethod(.monotone)
                LineMark(
                    x: .value("Date", bucket.date),
                    y: .value("Turnover", bucket.amount)
                )
                .foregroundStyle(Color.industryAccent)
                .lineStyle(StrokeStyle(lineWidth: 1.4))
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
            Text("NO DATA IN THIS PERIOD")
                .industryKicker()
                .foregroundStyle(Color.industryFaint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart(Array(zip(buckets, values)), id: \.0.id) { bucket, value in
                AreaMark(
                    x: .value("Date", bucket.date, unit: range.calendarComponent),
                    y: .value(metric.label, value)
                )
                .foregroundStyle(Color.industryAccentTint)
                .interpolationMethod(.monotone)
                LineMark(
                    x: .value("Date", bucket.date, unit: range.calendarComponent),
                    y: .value(metric.label, value)
                )
                .foregroundStyle(Color.industryAccent)
                .lineStyle(StrokeStyle(lineWidth: 1.6))
                .interpolationMethod(.monotone)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: range.axisFormat)
                        .font(IndustryFont.kicker(9))
                        .foregroundStyle(Color.industryFaint)
                    AxisTick().foregroundStyle(Color.clear)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Color.industryHair)
                    AxisTick().foregroundStyle(Color.clear)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(axisLabel(number))
                                .font(IndustryFont.display(11))
                                .foregroundStyle(Color.industryFaint)
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
                Rectangle()
                    .fill(Double(index) < fraction * 20 ? Color.industryAccent : Color.industryHair)
                    .frame(height: 5)
            }
        }
    }
}
