//
//  JSONParsingTests.swift
//  ShopwareAppTests
//
//  Covers the free helpers that decode Shopware Admin API responses — the
//  fragile glue between the API's JSON:API / plain-JSON shapes and the models.
//

import XCTest
@testable import ShopwareApp

final class JSONParsingTests: XCTestCase {

    // MARK: - entityAttributes

    func testEntityAttributes_unwrapsJSONAPIAttributes() {
        let row: [String: Any] = ["id": "1", "attributes": ["name": "Hello", "stock": 5]]
        let attrs = entityAttributes(of: row)
        XCTAssertEqual(attrs["name"] as? String, "Hello")
        XCTAssertEqual(attrs["stock"] as? Int, 5)
        XCTAssertNil(attrs["id"], "The id lives on the row, not inside attributes")
    }

    func testEntityAttributes_passesThroughPlainJSON() {
        let row: [String: Any] = ["name": "Plain", "stock": 9]
        let attrs = entityAttributes(of: row)
        XCTAssertEqual(attrs["name"] as? String, "Plain")
        XCTAssertEqual(attrs["stock"] as? Int, 9)
    }

    // MARK: - relationshipID

    func testRelationshipID_extractsNestedDataID() {
        let rel: [String: Any] = ["data": ["type": "currency", "id": "eur-123"]]
        XCTAssertEqual(relationshipID(from: rel), "eur-123")
    }

    func testRelationshipID_returnsNilForMalformed() {
        XCTAssertNil(relationshipID(from: nil))
        XCTAssertNil(relationshipID(from: ["data": "not-a-dict"]))
        XCTAssertNil(relationshipID(from: ["nope": [:]]))
    }

    // MARK: - translatedName

    func testTranslatedName_prefersTranslatedBlock() {
        let attrs: [String: Any] = ["translated": ["name": "Übersetzt"], "name": "raw"]
        XCTAssertEqual(translatedName(from: attrs), "Übersetzt")
    }

    func testTranslatedName_nilWhenAbsent() {
        XCTAssertNil(translatedName(from: ["name": "raw"]))
    }

    // MARK: - orderStateTechnicalName

    func testOrderState_prefersEmbeddedTechnicalName() {
        let attrs: [String: Any] = [
            "stateMachineState": ["technicalName": "in_progress", "translated": ["name": "In Bearbeitung"]]
        ]
        XCTAssertEqual(orderStateTechnicalName(from: attrs, includedState: nil), "in_progress")
    }

    func testOrderState_fallsBackToIncludedTechnicalName() {
        let included: [String: Any] = ["technicalName": "open"]
        XCTAssertEqual(orderStateTechnicalName(from: [:], includedState: included), "open")
    }

    func testOrderState_unknownWhenNothingPresent() {
        XCTAssertEqual(orderStateTechnicalName(from: [:], includedState: nil), "Unknown")
    }

    // MARK: - decimal(from:)

    func testDecimal_fromVariousTypes() {
        XCTAssertEqual(decimal(from: Decimal(12.5)), Decimal(12.5))
        XCTAssertEqual(decimal(from: NSNumber(value: 7)), Decimal(7))
        XCTAssertEqual(decimal(from: "3.14"), Decimal(string: "3.14"))
        XCTAssertEqual(decimal(from: "not-a-number"), 0)
        XCTAssertEqual(decimal(from: nil), 0)
    }

    // MARK: - parseHistogramDate

    func testParseHistogramDate_dayFormat() {
        let date = parseHistogramDate("2026-06-01")
        XCTAssertNotNil(date)
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date!)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 6)
        XCTAssertEqual(comps.day, 1)
    }

    func testParseHistogramDate_hourFormat() {
        let date = parseHistogramDate("2026-06-01 10:00:00")
        XCTAssertNotNil(date)
        let comps = Calendar.current.dateComponents([.hour], from: date!)
        XCTAssertEqual(comps.hour, 10)
    }

    func testParseHistogramDate_rejectsGarbage() {
        XCTAssertNil(parseHistogramDate("nonsense"))
        XCTAssertNil(parseHistogramDate(""))
    }

    // MARK: - errorMessage(from:status:)

    func testErrorMessage_extractsDetail() {
        let payload: [String: Any] = ["errors": [["detail": "Something broke"]]]
        XCTAssertEqual(errorMessage(from: payload, status: 400), "Something broke")
    }

    func testErrorMessage_fallsBackToStatus() {
        XCTAssertEqual(errorMessage(from: ["unexpected": true], status: 503),
                       "Shopware request failed with status 503.")
    }

    func testErrorMessage_rewritesAuthFailure() {
        let payload: [String: Any] = ["errors": [["detail": "The client authentication failed"]]]
        let message = errorMessage(from: payload, status: 401)
        XCTAssertTrue(message.contains("Access key ID"),
                      "Auth failures should be rewritten into actionable guidance")
    }
}
