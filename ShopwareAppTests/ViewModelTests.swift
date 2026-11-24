import XCTest
@testable import ShopwareApp

final class ViewModelTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    @MainActor
    func testProductsViewModelBuildsChannelSearchAndClampsNegativeStock() async throws {
        MockURLProtocol.install { request in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/search/product"):
                return .json(
                    #"""
                    {
                      "data": [{
                        "id": "product-1",
                        "attributes": {
                          "name": "Raw mug",
                          "translated": {"name": "Shopware mug"},
                          "productNumber": "SW-MUG",
                          "stock": 4,
                          "active": true,
                          "price": [{"gross": 19.95}]
                        }
                      }]
                    }
                    """#
                )
            case ("PATCH", "/api/product/product-1"):
                return .empty()
            default:
                return .json("{}", statusCode: 404)
            }
        }

        let viewModel = ProductsViewModel(
            client: TestHTTPFactory.client(cachedToken: "token"),
            salesChannelID: "storefront-channel",
            currencyCode: "EUR"
        )

        let products = try await viewModel.loadProducts(term: " mug ").products
        XCTAssertEqual(products.count, 1)
        XCTAssertEqual(products[0].name, "Shopware mug")
        XCTAssertEqual(products[0].productNumber, "SW-MUG")
        XCTAssertEqual(products[0].stock, 4)
        XCTAssertEqual(products[0].price, Decimal(string: "19.95"))

        try await viewModel.setStock(productID: "product-1", to: -5)

        let requests = MockURLProtocol.capturedRequests()
        let searchBody = try TestHTTPFactory.jsonBody(of: requests[0])
        XCTAssertEqual(searchBody["term"] as? String, "mug")
        let filters = searchBody["filter"] as? [[String: Any]]
        XCTAssertEqual(filters?.first?["field"] as? String, "visibilities.salesChannelId")
        XCTAssertEqual(filters?.first?["value"] as? String, "storefront-channel")

        let updateBody = try TestHTTPFactory.jsonBody(of: requests[1])
        XCTAssertEqual(updateBody["stock"] as? Int, 0)
    }

    @MainActor
    func testProductsViewModelRequestsPagesWithTotalAndStockFilter() async throws {
        MockURLProtocol.install { _ in
            .json(
                #"""
                {
                  "meta": {"total": 530},
                  "data": [{"id": "product-51", "attributes": {"name": "Cap", "productNumber": "SW-CAP", "stock": 3}}]
                }
                """#
            )
        }

        let viewModel = ProductsViewModel(
            client: TestHTTPFactory.client(cachedToken: "token"),
            salesChannelID: nil,
            currencyCode: "EUR"
        )

        let page = try await viewModel.loadProducts(term: "", stockFilter: .low, page: 2)
        XCTAssertEqual(page.total, 530)
        XCTAssertEqual(page.products.map(\.id), ["product-51"])

        let body = try TestHTTPFactory.jsonBody(of: MockURLProtocol.capturedRequests()[0])
        XCTAssertEqual(body["page"] as? Int, 2)
        XCTAssertEqual(body["limit"] as? Int, ProductsViewModel.pageSize)
        XCTAssertEqual(body["total-count-mode"] as? Int, 1)
        let filters = body["filter"] as? [[String: Any]] ?? []
        XCTAssertEqual(filters.count, 1)
        XCTAssertEqual(filters.first?["field"] as? String, "stock")
        XCTAssertEqual(filters.first?["type"] as? String, "range")
        XCTAssertEqual((filters.first?["parameters"] as? [String: Any])?["lte"] as? Int, 10)
    }

    @MainActor
    func testProductsViewModelOutOfStockFilterIncludesNegativeStock() async throws {
        MockURLProtocol.install { _ in .json(#"{"meta":{"total":0},"data":[]}"#) }
        let viewModel = ProductsViewModel(
            client: TestHTTPFactory.client(cachedToken: "token"),
            salesChannelID: nil,
            currencyCode: "EUR"
        )

        let page = try await viewModel.loadProducts(term: "", stockFilter: .out)
        XCTAssertEqual(page.total, 0)

        let body = try TestHTTPFactory.jsonBody(of: MockURLProtocol.capturedRequests()[0])
        let filter = (body["filter"] as? [[String: Any]])?.first
        XCTAssertEqual((filter?["parameters"] as? [String: Any])?["lte"] as? Int, 0)
    }

    @MainActor
    func testProductsViewModelCountsActiveMainProductsInChannel() async throws {
        MockURLProtocol.install { request in
            XCTAssertEqual(request.url?.path, "/api/search/product")
            return .json(#"{"meta":{"total":530},"data":[]}"#)
        }
        let viewModel = ProductsViewModel(
            client: TestHTTPFactory.client(cachedToken: "token"),
            salesChannelID: "storefront-channel",
            currencyCode: "EUR"
        )

        let count = try await viewModel.activeProductCount()
        XCTAssertEqual(count, 530)

        let body = try TestHTTPFactory.jsonBody(of: MockURLProtocol.capturedRequests()[0])
        let filters = body["filter"] as? [[String: Any]] ?? []
        XCTAssertTrue(filters.contains { $0["field"] as? String == "active" && $0["value"] as? Bool == true })
        XCTAssertTrue(filters.contains { $0["field"] as? String == "parentId" && $0["value"] is NSNull })
        XCTAssertTrue(filters.contains {
            $0["field"] as? String == "visibilities.salesChannelId" && $0["value"] as? String == "storefront-channel"
        })
    }

    @MainActor
    func testProductsMergeSkipsRowsAlreadyShown() {
        func product(_ id: String) -> ProductSummary {
            ProductSummary(id: id, name: id, productNumber: id, stock: 1, active: true, price: nil, coverURL: nil)
        }
        let merged = ProductsViewModel.merge([product("a"), product("b")], with: [product("b"), product("c")])
        XCTAssertEqual(merged.map(\.id), ["a", "b", "c"])
    }

    @MainActor
    func testPaymentMethodsParseFlowChannelsAndToggle() async throws {
        MockURLProtocol.install { request in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/search/payment-method"):
                return .json(
                    #"""
                    {
                      "data": [
                        {
                          "id": "pm-invoice",
                          "attributes": {"name": "Invoice", "translated": {"name": "Rechnung", "description": " Pay later "},
                                         "active": true, "position": 1, "synchronous": true, "asynchronous": false},
                          "relationships": {"salesChannels": {"data": [{"type": "sales_channel", "id": "sc-1"}, {"type": "sales_channel", "id": "sc-2"}]}}
                        },
                        {
                          "id": "pm-paypal",
                          "attributes": {"name": "PayPal", "active": false, "position": 2, "asynchronous": true},
                          "relationships": {"salesChannels": {"data": []}}
                        },
                        {
                          "id": "pm-custom",
                          "attributes": {"name": "Custom", "active": true, "position": 3}
                        }
                      ]
                    }
                    """#
                )
            case ("PATCH", "/api/payment-method/pm-paypal"):
                return .empty()
            default:
                return .json("{}", statusCode: 404)
            }
        }

        let settings = ShopSettingsViewModel(client: TestHTTPFactory.client(cachedToken: "token"))
        let methods = try await settings.paymentMethods()

        XCTAssertEqual(methods.map(\.id), ["pm-invoice", "pm-paypal", "pm-custom"])
        XCTAssertEqual(methods[0].name, "Rechnung")
        XCTAssertEqual(methods[0].description, "Pay later")
        XCTAssertEqual(methods[0].flow, .direct)
        XCTAssertEqual(methods[0].salesChannelIDs, ["sc-1", "sc-2"])
        XCTAssertEqual(methods[1].flow, .redirect)
        XCTAssertFalse(methods[1].active)
        XCTAssertEqual(methods[1].salesChannelIDs, [])
        XCTAssertEqual(methods[2].flow, .unknown)

        try await settings.setPaymentMethodActive(paymentMethodID: "pm-paypal", active: true)

        let requests = MockURLProtocol.capturedRequests()
        let searchBody = try TestHTTPFactory.jsonBody(of: requests[0])
        XCTAssertNotNil((searchBody["associations"] as? [String: Any])?["salesChannels"])
        let patchBody = try TestHTTPFactory.jsonBody(of: requests[1])
        XCTAssertEqual(patchBody["active"] as? Bool, true)
    }

    @MainActor
    func testLastActivePaymentMethodIsDetected() {
        func method(_ id: String, active: Bool) -> PaymentMethod {
            PaymentMethod(id: id, name: id, description: nil, active: active, position: 0, flow: .direct, salesChannelIDs: [])
        }
        let oneActive = [method("a", active: true), method("b", active: false)]
        XCTAssertTrue(ShopSettingsViewModel.wouldDisableLastActiveMethod("a", in: oneActive))
        XCTAssertFalse(ShopSettingsViewModel.wouldDisableLastActiveMethod("b", in: oneActive))
        let twoActive = [method("a", active: true), method("b", active: true)]
        XCTAssertFalse(ShopSettingsViewModel.wouldDisableLastActiveMethod("a", in: twoActive))
    }

    @MainActor
    func testOrderDetailViewModelRefreshesAfterSuccessfulTransition() async throws {
        MockURLProtocol.install { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(
                request.url?.path,
                "/api/_action/state-machine/order/order-1/state/process"
            )
            return .empty()
        }

        var refreshCount = 0
        let viewModel = OrderDetailViewModel(
            client: TestHTTPFactory.client(cachedToken: "token")
        ) {
            refreshCount += 1
        }

        try await viewModel.performTransition(
            entityName: "order",
            entityID: "order-1",
            action: "process"
        )

        XCTAssertEqual(refreshCount, 1)
    }

    @MainActor
    func testDashboardAttentionItemsUseFriendlyOutOfStockStateAndCanDismiss() {
        let previousLanguage = UserDefaults.standard.object(forKey: "appLanguage")
        UserDefaults.standard.set("en", forKey: "appLanguage")
        defer {
            if let previousLanguage {
                UserDefaults.standard.set(previousLanguage, forKey: "appLanguage")
            } else {
                UserDefaults.standard.removeObject(forKey: "appLanguage")
            }
        }

        let viewModel = ShopwareDashboardViewModel()
        viewModel.metrics = DashboardMetrics(
            orderCountToday: 1,
            openOrderCount: 1,
            productCount: 1,
            customerCount: 1,
            todayRevenue: 42,
            currencyCode: "EUR",
            latestOrders: [
                LatestOrder(
                    id: "order-1",
                    orderNumber: "10001",
                    amountTotal: 42,
                    orderDateTime: nil,
                    currencyCode: "EUR",
                    state: "open"
                )
            ]
        )
        viewModel.lowStockProducts = [
            LowStockProduct(
                id: "product-1",
                name: "Shopware mug",
                productNumber: "SW-MUG",
                stock: -2
            )
        ]

        let items = viewModel.attentionItems
        XCTAssertEqual(items.count, 2)

        let stockItem = items.first { $0.id == "stock-product-1" }
        XCTAssertEqual(stockItem?.severity, 3)
        XCTAssertEqual(stockItem?.title, "Shopware mug is out of stock")
        XCTAssertEqual(stockItem?.meta, "SW-MUG · Out of stock")
        XCTAssertFalse(stockItem?.meta.contains("-2") ?? true)
        XCTAssertEqual(stockItem?.action, "Restock")

        viewModel.dismissAttentionItem("stock-product-1")
        XCTAssertNil(viewModel.attentionItems.first { $0.id == "stock-product-1" })
        XCTAssertNotNil(viewModel.attentionItems.first { $0.id == "order-order-1" })
    }

    @MainActor
    func testDashboardChannelSharesUseOrderCountsAndHideWhenEmpty() {
        let viewModel = ShopwareDashboardViewModel()
        XCTAssertEqual(viewModel.channelShareLabel(for: nil), "100%")
        XCTAssertEqual(viewModel.channelShareLabel(for: "storefront"), "—")

        viewModel.channelOrderCounts = [
            "storefront": 78,
            "headless": 22
        ]
        XCTAssertEqual(viewModel.channelShareLabel(for: "storefront"), "78%")
        XCTAssertEqual(viewModel.channelShareLabel(for: "headless"), "22%")
        XCTAssertEqual(viewModel.channelShareLabel(for: "unused"), "0%")
        XCTAssertEqual(viewModel.channelShareLabel(for: nil), "100%")
    }

    @MainActor
    func testDashboardShopStatusUsesMaintenanceInsteadOfPlaceholder() {
        let previousLanguage = UserDefaults.standard.object(forKey: "appLanguage")
        UserDefaults.standard.set("en", forKey: "appLanguage")
        defer {
            if let previousLanguage {
                UserDefaults.standard.set(previousLanguage, forKey: "appLanguage")
            } else {
                UserDefaults.standard.removeObject(forKey: "appLanguage")
            }
        }

        let viewModel = ShopwareDashboardViewModel()
        viewModel.salesChannels = [
            SalesChannel(id: "storefront", name: "Storefront", maintenance: false)
        ]
        XCTAssertEqual(viewModel.shopStatusLabel, "VIEW")
        XCTAssertFalse(viewModel.hasMaintenanceChannel)

        viewModel.salesChannels = [
            SalesChannel(id: "storefront", name: "Storefront", maintenance: true)
        ]
        XCTAssertEqual(viewModel.shopStatusLabel, "MAINTENANCE")
        XCTAssertTrue(viewModel.hasMaintenanceChannel)
    }
}
