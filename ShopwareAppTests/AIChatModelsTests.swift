//
//  AIChatModelsTests.swift
//  ShopwareAppTests
//

import XCTest
@testable import ShopwareApp

@MainActor
final class AIChatModelsTests: XCTestCase {
    func testJSONValuePreservesLargeIntegerExactly() throws {
        let source = Data("9223372036854775806".utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: source)
        XCTAssertEqual(value, .integer(9_223_372_036_854_775_806))
        XCTAssertEqual(try JSONEncoder().encode(value), source)
    }

    func testChatResponseDecodesCacheUsageAndApproval() throws {
        let data = Data("""
        {
          "content": [{"type":"text","text":"Ready"}],
          "stop_reason": "end_turn",
          "usage": {
            "input_tokens": 10,
            "output_tokens": 4,
            "cache_creation_input_tokens": 20,
            "cache_read_input_tokens": 30
          },
          "approval": {
            "token": "opaque",
            "expires_at": 2000000000000,
            "actions": [{
              "fingerprint": "abc",
              "tool": "product-update",
              "summary": "product-update: stock 4"
            }]
          }
        }
        """.utf8)

        let response = try JSONDecoder().decode(AIChatResponse.self, from: data)
        XCTAssertEqual(response.usage?.totalInputTokens, 60)
        XCTAssertEqual(response.usage?.outputTokens, 4)
        XCTAssertEqual(response.approval?.actions.first?.tool, "product-update")
    }

    func testToolDisplayNameIsReadable() {
        XCTAssertEqual(AIChatViewModel.displayName(forTool: "product_stock-update"), "product stock update")
    }
}
