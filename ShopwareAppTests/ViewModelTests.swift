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

        let products = try await viewModel.searchProducts(term: " mug ")
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
