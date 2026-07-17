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

    func testAssistantAccessSupportsEverySubscriptionAndKeyCombination() {
        XCTAssertEqual(
            AIAssistantAccessMode(isSubscribed: false, hasPersonalKey: false),
            .unavailable
        )
        XCTAssertEqual(
            AIAssistantAccessMode(isSubscribed: true, hasPersonalKey: false),
            .subscription
        )
        XCTAssertEqual(
            AIAssistantAccessMode(isSubscribed: false, hasPersonalKey: true),
            .personalKey
        )
        XCTAssertEqual(
            AIAssistantAccessMode(isSubscribed: true, hasPersonalKey: true),
            .personalKey
        )
    }

    func testProviderDetectionUsesUnambiguousKeyPrefixes() {
        XCTAssertEqual(AIProvider.detect(from: " sk-ant-api03-example "), .anthropic)
        XCTAssertEqual(AIProvider.detect(from: "sk-proj-example"), .openAI)
        XCTAssertEqual(AIProvider.detect(from: "AIzaSyExample"), .gemini)
        XCTAssertNil(AIProvider.detect(from: "provider-specific-secret"))
    }

    func testProviderCredentialRoundTrips() throws {
        let credential = AIProviderCredential(provider: .gemini, key: "AIza-example")
        let decoded = try JSONDecoder().decode(
            AIProviderCredential.self,
            from: JSONEncoder().encode(credential)
        )
        XCTAssertEqual(decoded, credential)
    }

    func testOpenAIResponseNormalizesMCPForNativeApproval() throws {
        let raw = try JSONDecoder().decode(JSONValue.self, from: Data(#"""
        {
          "output": [
            {"type":"message","content":[{"type":"output_text","text":"I found it."}]},
            {"type":"mcp_call","id":"call_1","name":"product-update","arguments":"{\"stock\":4}","output":"Approval required"}
          ],
          "usage":{"input_tokens":12,"output_tokens":5}
        }
        """#.utf8))

        let result = AIProviderResponseNormalizer.openAI(raw)
        XCTAssertEqual(result.content.first, .text("I found it."))
        XCTAssertEqual(result.usage?.inputTokens, 12)
        XCTAssertEqual(result.usage?.outputTokens, 5)
        XCTAssertTrue(result.content.contains(.other(.object([
            "type": .string("mcp_tool_use"),
            "id": .string("call_1"),
            "name": .string("product-update"),
            "input": .object(["stock": .integer(4)])
        ]))))
    }

    func testGeminiInteractionNormalizesMCPForNativeApproval() throws {
        let raw = try JSONDecoder().decode(JSONValue.self, from: Data(#"""
        {
          "steps":[
            {"type":"mcp_server_tool_call","id":"step_1","server_name":"shopware","name":"order-transition","arguments":{"state":"shipped"}},
            {"type":"mcp_server_tool_result","call_id":"step_1","server_name":"shopware","name":"order-transition","result":{"status":"blocked"}},
            {"type":"model_output","content":[{"type":"text","text":"Ready to update."}]}
          ],
          "usage":{"total_input_tokens":20,"total_output_tokens":7}
        }
        """#.utf8))

        let result = AIProviderResponseNormalizer.gemini(raw)
        XCTAssertTrue(result.content.contains(.text("Ready to update.")))
        XCTAssertEqual(result.usage?.inputTokens, 20)
        XCTAssertEqual(result.usage?.outputTokens, 7)
        XCTAssertTrue(result.content.contains(.other(.object([
            "type": .string("mcp_tool_use"),
            "id": .string("step_1"),
            "name": .string("order-transition"),
            "input": .object(["state": .string("shipped")])
        ]))))
        let normalizedTypes = result.content.compactMap { block -> String? in
            guard case .other(let raw) = block else { return nil }
            return raw["type"]?.stringValue
        }
        XCTAssertEqual(normalizedTypes.filter { $0 == "mcp_tool_use" }.count, 1)
        XCTAssertEqual(normalizedTypes.filter { $0 == "mcp_tool_result" }.count, 1)
    }
}
