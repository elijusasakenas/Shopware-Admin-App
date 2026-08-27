//
//  ShopwareConnectionTests.swift
//  ShopwareAppTests
//
//  URL normalization and the tolerant decoding that migrates connections
//  saved by the original single-shop build (no id / label fields).
//

import XCTest
@testable import ShopwareApp

final class ShopwareConnectionTests: XCTestCase {

    // MARK: - URL normalization

    func testNormalizedBaseURL_addsHTTPSWhenSchemeMissing() throws {
        let c = ShopwareConnection(shopURL: "shop.example.com", accessKey: "k", secretKey: "s")
        XCTAssertEqual(try c.resolvedBaseURL().scheme, "https")
        XCTAssertEqual(try c.resolvedBaseURL().host, "shop.example.com")
    }

    func testNormalizedBaseURL_preservesExistingScheme() throws {
        let c = ShopwareConnection(shopURL: "http://localhost:8000", accessKey: "k", secretKey: "s")
        XCTAssertEqual(try c.resolvedBaseURL().scheme, "http")
        XCTAssertEqual(try c.resolvedBaseURL().host, "localhost")
    }

    func testNormalizedBaseURL_trimsWhitespaceAndTrailingSlash() throws {
        let c = ShopwareConnection(shopURL: "  https://shop.example.com/  ", accessKey: "k", secretKey: "s")
        XCTAssertEqual(try c.resolvedBaseURL().absoluteString, "https://shop.example.com")
    }

    func testNormalizedURL_rejectsInvalidValues() {
        XCTAssertNil(ShopwareConnection.normalizedURL(from: ""))
        XCTAssertNil(ShopwareConnection.normalizedURL(from: "   "))
        XCTAssertNil(ShopwareConnection.normalizedURL(from: "https://"))
        XCTAssertNil(ShopwareConnection.normalizedURL(from: "ftp://shop.example.com"))
        XCTAssertNil(ShopwareConnection.normalizedURL(from: "not a url"))
    }

    func testResolvedBaseURL_throwsInsteadOfUsingExampleDotCom() {
        let previousLanguage = UserDefaults.standard.object(forKey: "appLanguage")
        UserDefaults.standard.set("en", forKey: "appLanguage")
        defer {
            if let previousLanguage {
                UserDefaults.standard.set(previousLanguage, forKey: "appLanguage")
            } else {
                UserDefaults.standard.removeObject(forKey: "appLanguage")
            }
        }

        let c = ShopwareConnection(shopURL: "not a url", accessKey: "k", secretKey: "s")
        XCTAssertEqual(c.displayHost, "not a url")
        XCTAssertThrowsError(try c.resolvedBaseURL()) { error in
            XCTAssertTrue(error.shopwareDisplayMessage.contains("valid shop URL"))
        }
    }

    // MARK: - displayName / displayHost

    func testDisplayName_prefersLabel() {
        let c = ShopwareConnection(shopURL: "https://shop.example.com", accessKey: "k", secretKey: "s", label: "My Store")
        XCTAssertEqual(c.displayName, "My Store")
    }

    func testDisplayName_fallsBackToHostWhenLabelBlank() {
        let c = ShopwareConnection(shopURL: "https://shop.example.com", accessKey: "k", secretKey: "s", label: "   ")
        XCTAssertEqual(c.displayName, "shop.example.com")
    }

    func testDisplayName_fallsBackToHostWhenNoLabel() {
        let c = ShopwareConnection(shopURL: "https://shop.example.com", accessKey: "k", secretKey: "s")
        XCTAssertEqual(c.displayName, "shop.example.com")
    }

    // MARK: - Codable round-trip

    func testCodable_roundTripPreservesAllFields() throws {
        let original = ShopwareConnection(shopURL: "https://a.com", accessKey: "key", secretKey: "sec", label: "Label")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ShopwareConnection.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.label, "Label")
    }

    // MARK: - Legacy migration (the important one)

    func testDecode_legacyPayloadWithoutIDSynthesizesStableID() throws {
        // The format saved by the original single-shop build: no id, no label.
        let legacyJSON = """
        { "shopURL": "https://legacy.example.com", "accessKey": "ak", "secretKey": "sk" }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ShopwareConnection.self, from: legacyJSON)
        XCTAssertEqual(decoded.shopURL, "https://legacy.example.com")
        XCTAssertEqual(decoded.accessKey, "ak")
        XCTAssertEqual(decoded.secretKey, "sk")
        XCTAssertNil(decoded.label)
        // A fresh id is synthesized so the connection has a stable identity.
        XCTAssertNotNil(UUID(uuidString: decoded.id.uuidString))
    }

    func testDecode_missingRequiredFieldThrows() {
        // secretKey is required; its absence should fail decoding.
        let bad = """
        { "shopURL": "https://x.com", "accessKey": "ak" }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(ShopwareConnection.self, from: bad))
    }
}
