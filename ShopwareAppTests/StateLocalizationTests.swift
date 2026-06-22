//
//  StateLocalizationTests.swift
//  ShopwareAppTests
//
//  StateLocalization turns Shopware technicalNames into display text. The
//  humanized fallback is fully deterministic; the catalog lookup depends on
//  bundled .strings, so those assertions stay loose (non-empty, not raw key).
//

import XCTest
@testable import ShopwareApp

final class StateLocalizationTests: XCTestCase {

    // MARK: - Humanized fallback (deterministic for unknown keys)

    func testUnknownState_isHumanized() {
        // A made-up key has no catalog entry, so it always takes the fallback.
        XCTAssertEqual(StateLocalization.stateName("paid_partially_custom"),
                       "Paid partially custom")
    }

    func testUnknownState_handlesHyphens() {
        XCTAssertEqual(StateLocalization.stateName("waiting-for-stock"),
                       "Waiting for stock")
    }

    func testUnknownState_singleWordIsCapitalized() {
        XCTAssertEqual(StateLocalization.stateName("frobnicated"), "Frobnicated")
    }

    func testEmptyState_doesNotCrashAndIsNonEmpty() {
        XCTAssertFalse(StateLocalization.stateName("").isEmpty)
        XCTAssertFalse(StateLocalization.stateName("   ").isEmpty)
    }

    // MARK: - Known states (catalog or fallback — never the raw snake_case key)

    func testKnownStates_neverReturnRawTechnicalName() {
        for key in ["open", "in_progress", "completed", "cancelled",
                    "paid", "paid_partially", "shipped", "returned_partially"] {
            let result = StateLocalization.stateName(key)
            XCTAssertFalse(result.isEmpty)
            XCTAssertFalse(result.contains("_"),
                           "\(key) rendered with an underscore — not humanized or localized")
        }
    }

    func testTransitionName_usesSameMapping() {
        // transitionName carries the destination state's technicalName.
        XCTAssertEqual(StateLocalization.transitionName("custom_done_state"),
                       "Custom done state")
    }
}
