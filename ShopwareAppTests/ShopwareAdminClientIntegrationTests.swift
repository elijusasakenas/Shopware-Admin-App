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

    func testFetchChannelBreakdownMapsOrderShares() async throws {
        MockURLProtocol.install { request in
            XCTAssertEqual(request.url?.path, "/api/search/order")
            return .json(
                #"""
                {
                  "aggregations": {
                    "channels": {
                      "buckets": [
                        { "key": "storefront", "count": 78 },
                        { "key": "headless", "count": 22 }
                      ]
                    }
                  }
                }
                """#
            )
        }

        let client = TestHTTPFactory.client(cachedToken: "token")
        let counts = try await client.fetchChannelBreakdown(since: DateRange.days30.sinceDate)

        XCTAssertEqual(counts["storefront"], 78)
        XCTAssertEqual(counts["headless"], 22)

        let body = try TestHTTPFactory.jsonBody(of: MockURLProtocol.capturedRequests()[0])
        let filters = body["filter"] as? [[String: Any]]
        XCTAssertEqual(filters?.first?["field"] as? String, "orderDateTime")
        let aggregations = body["aggregations"] as? [[String: Any]]
        XCTAssertEqual(aggregations?.first?["field"] as? String, "salesChannelId")
    }

    func testCountRecentCustomersFiltersCreatedAtAndReadsTotal() async throws {
        MockURLProtocol.install { request in
            XCTAssertEqual(request.url?.path, "/api/search/customer")
            return .json(#"{"meta":{"total":18},"data":[]}"#)
        }

        let since = DateRange.days7.sinceDate
        let client = TestHTTPFactory.client(cachedToken: "token")
        let count = try await client.countRecentCustomers(since: since)

        XCTAssertEqual(count, 18)
        let body = try TestHTTPFactory.jsonBody(of: MockURLProtocol.capturedRequests()[0])
        let filters = body["filter"] as? [[String: Any]]
        XCTAssertEqual(filters?.first?["field"] as? String, "createdAt")
        XCTAssertEqual(filters?.first?["type"] as? String, "range")
        let parameters = filters?.first?["parameters"] as? [String: Any]
        XCTAssertEqual(parameters?["gte"] as? String, since.iso8601String)
    }

    func testFetchRecentCustomersAppliesSinceFilter() async throws {
        MockURLProtocol.install { request in
            XCTAssertEqual(request.url?.path, "/api/search/customer")
            return .json(
                #"""
                {
                  "data": [{
                    "id": "customer-1",
                    "attributes": {
                      "firstName": "Ada",
                      "lastName": "Lovelace",
                      "email": "ada@example.test",
                      "guest": false
                    }
                  }]
                }
                """#
            )
        }

        let since = DateRange.days7.sinceDate
        let client = TestHTTPFactory.client(cachedToken: "token")
        let customers = try await client.fetchRecentCustomers(since: since)

        XCTAssertEqual(customers.count, 1)
        XCTAssertEqual(customers[0].name, "Ada Lovelace")
        let body = try TestHTTPFactory.jsonBody(of: MockURLProtocol.capturedRequests()[0])
        XCTAssertEqual(body["limit"] as? Int, 100)
        let filters = body["filter"] as? [[String: Any]]
        XCTAssertEqual(filters?.first?["field"] as? String, "createdAt")
    }

    func testConcurrentAccessTokenFetchesOAuthOnce() async throws {
        MockURLProtocol.install { request in
            XCTAssertEqual(request.url?.path, "/api/oauth/token")
            return .json(#"{"access_token":"shared-token","expires_in":600}"#)
        }

        let client = TestHTTPFactory.client()
        async let first = client.accessToken()
        async let second = client.accessToken()
        async let third = client.accessToken()
        let tokens = try await [first, second, third]

        XCTAssertEqual(Set(tokens), ["shared-token"])
        let oauthCalls = MockURLProtocol.capturedRequests().filter { $0.url?.path == "/api/oauth/token" }
        XCTAssertEqual(oauthCalls.count, 1)
    }
}
