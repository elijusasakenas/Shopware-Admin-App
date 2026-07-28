import XCTest
@testable import ShopwareApp

final class ShopwareAdminClientIntegrationTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testFetchPromotionsAuthenticatesAndMapsJSONAPIResponse() async throws {
        MockURLProtocol.install { request in
            switch request.url?.path {
            case "/api/oauth/token":
                return .json(#"{"access_token":"token-123","expires_in":600}"#)
            case "/api/search/promotion":
                return .json(
                    #"""
                    {
                      "data": [{
                        "id": "promotion-1",
                        "attributes": {
                          "name": "Raw name",
                          "translated": {"name": "Summer sale"},
                          "active": true,
                          "code": "SUMMER"
                        }
                      }]
                    }
                    """#
                )
            default:
                return .json(#"{"errors":[{"detail":"Unexpected request"}]}"#, statusCode: 404)
            }
        }

        let client = TestHTTPFactory.client()
        let promotions = try await client.fetchPromotions()

        XCTAssertEqual(promotions.count, 1)
        XCTAssertEqual(promotions[0].id, "promotion-1")
        XCTAssertEqual(promotions[0].name, "Summer sale")
        XCTAssertTrue(promotions[0].active)
        XCTAssertEqual(promotions[0].code, "SUMMER")

        let requests = MockURLProtocol.capturedRequests()
        XCTAssertEqual(requests.map(\.url?.path), [
            "/api/oauth/token",
            "/api/search/promotion"
        ])

        let tokenBody = try TestHTTPFactory.jsonBody(of: requests[0])
        XCTAssertEqual(tokenBody["grant_type"] as? String, "client_credentials")
        XCTAssertEqual(tokenBody["client_id"] as? String, "access-key")
        XCTAssertEqual(tokenBody["client_secret"] as? String, "secret-key")

        XCTAssertEqual(requests[1].httpMethod, "POST")
        XCTAssertEqual(
            requests[1].value(forHTTPHeaderField: "Authorization"),
            "Bearer token-123"
        )
        let searchBody = try TestHTTPFactory.jsonBody(of: requests[1])
        XCTAssertEqual(searchBody["limit"] as? Int, 100)
    }

    func testUnauthorizedResponseRefreshesTokenAndRetriesOnce() async throws {
        var infoAttempts = 0
        MockURLProtocol.install { request in
            switch request.url?.path {
            case "/api/_info/version":
                infoAttempts += 1
                if infoAttempts == 1 {
                    return .json(
                        #"{"errors":[{"detail":"Token expired"}]}"#,
                        statusCode: 401
                    )
                }
                return .json(#"{"version":"6.7.11.0"}"#)
            case "/api/oauth/token":
                return .json(#"{"access_token":"fresh-token","expires_in":600}"#)
            default:
                return .json("{}", statusCode: 404)
            }
        }

        let client = TestHTTPFactory.client(cachedToken: "expired-token")
        let version = try await client.fetchShopwareVersion()

        XCTAssertEqual(version, "6.7.11.0")
        let requests = MockURLProtocol.capturedRequests()
        XCTAssertEqual(requests.map(\.url?.path), [
            "/api/_info/version",
            "/api/oauth/token",
            "/api/_info/version"
        ])
        XCTAssertEqual(
            requests[0].value(forHTTPHeaderField: "Authorization"),
            "Bearer expired-token"
        )
        XCTAssertEqual(
            requests[2].value(forHTTPHeaderField: "Authorization"),
            "Bearer fresh-token"
        )
    }

    func testAdminAPIErrorPreservesShopwareDetail() async {
        MockURLProtocol.install { _ in
            .json(
                #"{"errors":[{"detail":"Promotion does not exist"}]}"#,
                statusCode: 404
            )
        }

        let client = TestHTTPFactory.client(cachedToken: "token")

        do {
            try await client.setPromotionActive(promotionID: "missing", active: true)
            XCTFail("Expected the request to fail")
        } catch {
            XCTAssertTrue(error.shopwareDisplayMessage.contains("Promotion does not exist"))
        }
    }
}
