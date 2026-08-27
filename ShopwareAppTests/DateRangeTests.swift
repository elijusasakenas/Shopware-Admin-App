//
//  DateRangeTests.swift
//  ShopwareAppTests
//
//  DateRange drives every chart query. Its `sinceDate` is time-relative, so
//  these assert ordering and approximate offsets rather than exact instants.
//

import XCTest
@testable import ShopwareApp

final class DateRangeTests: XCTestCase {

    func testSinceDates_areOrderedFurthestBackFirst() {
        let now = Date()
        // 30 days ago < 14 < 7 < 24h-ish < yesterday < now
        XCTAssertLessThan(DateRange.days30.sinceDate, DateRange.days14.sinceDate)
        XCTAssertLessThan(DateRange.days14.sinceDate, DateRange.days7.sinceDate)
        XCTAssertLessThan(DateRange.days7.sinceDate, now)
        XCTAssertLessThan(DateRange.yesterday.sinceDate, now)
        XCTAssertLessThan(DateRange.hours24.sinceDate, now)
    }

    func testDays7_isRoughlySevenDaysBack() {
        let interval = Date().timeIntervalSince(DateRange.days7.sinceDate)
        // Between 7 and 8 days because days7 snaps to startOfDay (earlier than "now").
        XCTAssertGreaterThanOrEqual(interval, 7 * 86_400)
        XCTAssertLessThan(interval, 8 * 86_400)
    }

    func testHours24_isAboutADayBack() {
        let interval = Date().timeIntervalSince(DateRange.hours24.sinceDate)
        XCTAssertEqual(interval, 86_400, accuracy: 120, "hours24 should be ~24h before now")
    }

    func testHistogramInterval_isHourOnlyForIntradayRanges() {
        XCTAssertEqual(DateRange.hours24.histogramInterval, "hour")
        XCTAssertEqual(DateRange.yesterday.histogramInterval, "hour")
        XCTAssertEqual(DateRange.days7.histogramInterval, "day")
        XCTAssertEqual(DateRange.days14.histogramInterval, "day")
        XCTAssertEqual(DateRange.days30.histogramInterval, "day")
    }

    func testCalendarComponent_matchesInterval() {
        XCTAssertEqual(DateRange.hours24.calendarComponent, .hour)
        XCTAssertEqual(DateRange.yesterday.calendarComponent, .hour)
        XCTAssertEqual(DateRange.days30.calendarComponent, .day)
    }

    func testAllCases_haveStableRawValues() {
        // Raw values are persisted, so guard against accidental renames.
        XCTAssertEqual(DateRange.days30.rawValue, "30Days")
        XCTAssertEqual(DateRange.days14.rawValue, "14Days")
        XCTAssertEqual(DateRange.days7.rawValue, "7Days")
        XCTAssertEqual(DateRange.hours24.rawValue, "24Hours")
        XCTAssertEqual(DateRange.yesterday.rawValue, "Yesterday")
    }

    func testHalfOverHalfPercent_comparesTheTwoHalves() {
        XCTAssertNil(TrendComparison.halfOverHalfPercent([10]))
        XCTAssertEqual(TrendComparison.halfOverHalfPercent([10, 10, 20, 20]) ?? .nan, 100, accuracy: 0.01)
        XCTAssertEqual(TrendComparison.halfOverHalfPercent([20, 10]) ?? .nan, -50, accuracy: 0.01)
        XCTAssertNil(TrendComparison.halfOverHalfPercent([0, 8]))
    }

    func testDayOverDayPercent_usesYesterdayBucket() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let buckets = [
            DashboardBucket(date: yesterday, count: 2, amount: 100),
            DashboardBucket(date: today, count: 3, amount: 130)
        ]
        let change = TrendComparison.dayOverDayPercent(buckets: buckets, now: today, calendar: calendar)
        XCTAssertEqual(change ?? 0, 30, accuracy: 0.01)
    }
}
