//
//  ShopwareDashboardViewModel.swift
//  ShopwareApp
//
//  Session + dashboard state: credentials, shop switching, KPIs, charts, and
//  sales-channel selection. Feature screens use ProductsViewModel,
//  OrderDetailViewModel, and ShopSettingsViewModel with `apiClient`.
//

import Combine
import Foundation

@MainActor
final class ShopwareDashboardViewModel: ObservableObject {
    /// The shop currently shown on the dashboard, if any.
    @Published var connection: ShopwareConnection?
    /// Every shop saved on this device, for the shop switcher.
    @Published var savedConnections: [ShopwareConnection] = []
    /// True while the user is adding another shop on top of an active one.
    @Published var isAddingShop = false
    @Published var metrics: DashboardMetrics?
    @Published var orderBuckets: [DashboardBucket] = []
    @Published var revenueBuckets: [DashboardBucket] = []
    @Published var errorMessage: String?
    @Published var isBooting = true
    @Published var isLoading = false
    @Published var ordersRange: DateRange = .days30
    @Published var revenueRange: DateRange = .days30
    @Published var trendRange: DateRange = .days30
    @Published var trendMetric: TrendMetric = .orders
    @Published var isChannelPickerExpanded = false
    @Published var salesChannels: [SalesChannel] = []
    @Published var selectedChannelID: String?
    @Published var lowStockProducts: [LowStockProduct] = []
    @Published var topProducts: [TopProduct] = []
    @Published var languageStats: [LanguageStat] = []
    @Published var versionString = ""
    @Published private(set) var dismissedAttentionIDs: Set<String> = []

    var selectedChannelName: String {
        guard let id = selectedChannelID else { return AppLocalization.string("All sales channels") }
        return salesChannels.first { $0.id == id }?.name ?? AppLocalization.string("Sales channel")
    }

    var attentionItems: [AttentionItem] {
        var result: [AttentionItem] = []

        if let order = metrics?.latestOrders.first(where: {
            ["open", "in_progress"].contains($0.state)
        }) {
            result.append(
                AttentionItem(
                    id: "order-\(order.id)",
                    severity: 3,
                    title: AppLocalization.string("Order \(order.orderNumber) needs review"),
                    meta: "\(order.amountTotal.formatted(.currency(code: order.currencyCode))) · \(StateLocalization.stateName(order.state))",
                    action: AppLocalization.string("REVIEW"),
                    destination: .order(order)
                )
            )
        }

        if let product = lowStockProducts.first {
            result.append(
                AttentionItem(
                    id: "stock-\(product.id)",
                    severity: product.stock == 0 ? 3 : 2,
                    title: product.stock == 0
                        ? AppLocalization.string("\(product.name) is out of stock")
                        : AppLocalization.string("\(product.name) is running low"),
                    meta: AppLocalization.string(
                        "\(product.productNumber.isEmpty ? AppLocalization.string("PRODUCT") : product.productNumber) · \(product.stock) IN STOCK"
                    ),
                    action: AppLocalization.string("RESTOCK"),
                    destination: .products
                )
            )
        }

        return result
            .filter { !dismissedAttentionIDs.contains($0.id) }
            .sorted { $0.severity > $1.severity }
    }

    private let credentialStore = CredentialStore()
    private var client: ShopwareAdminClient?

    /// The active shop's API client, for features that drive the Admin API
    /// outside this view model (products, orders, settings, AI).
    var apiClient: ShopwareAdminClient? { client }

    func boot() async {
        guard isBooting else { return }
        do {
            savedConnections = try credentialStore.loadAll()
            // Reopen the shop that was active last time, falling back to the first.
            let active = savedConnections.first { $0.id == credentialStore.activeShopID }
                ?? savedConnections.first
            if let active {
                credentialStore.activeShopID = active.id
                connection = active
                client = ShopwareAdminClient(connection: active)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isBooting = false
    }

    /// Connect a brand-new shop: validate, save, make it active, and load it.
    func connect(_ nextConnection: ShopwareConnection) async {
        isLoading = true
        errorMessage = nil
        do {
            let client = ShopwareAdminClient(connection: nextConnection)
            try await client.testConnection()
            try credentialStore.save(nextConnection)
            credentialStore.activeShopID = nextConnection.id
            if let index = savedConnections.firstIndex(where: { $0.id == nextConnection.id }) {
                savedConnections[index] = nextConnection
            } else {
                savedConnections.append(nextConnection)
            }
            activate(nextConnection, client: client)
            salesChannels = (try? await client.fetchSalesChannels()) ?? []
            await loadAll()
            isAddingShop = false
        } catch {
            if !error.isCancellation {
                errorMessage = error.shopwareDisplayMessage
            }
            isLoading = false
        }
    }

    /// Switch the dashboard to an already-saved shop.
    func switchTo(_ target: ShopwareConnection) async {
        guard target.id != connection?.id else { return }
        credentialStore.activeShopID = target.id
        activate(target, client: ShopwareAdminClient(connection: target))
        await refresh()
    }

    /// Begin adding another shop without dropping the current one.
    func beginAddingShop() {
        errorMessage = nil
        isAddingShop = true
    }

    /// Cancel the add-shop flow (only meaningful when a shop is already active).
    func cancelAddingShop() {
        errorMessage = nil
        isAddingShop = false
    }

    /// Remove a saved shop. If it was the active one, fall back to another
    /// saved shop, or to the connect screen when none remain.
    func removeShop(_ target: ShopwareConnection) async {
        try? credentialStore.delete(id: target.id)
        savedConnections.removeAll { $0.id == target.id }

        guard target.id == connection?.id else { return }
        if let next = savedConnections.first {
            credentialStore.activeShopID = next.id
            activate(next, client: ShopwareAdminClient(connection: next))
            await refresh()
        } else {
            resetActiveShop()
        }
    }

    func refresh() async {
        guard let client else { return }
        if salesChannels.isEmpty {
            salesChannels = (try? await client.fetchSalesChannels()) ?? []
        }
        await loadAll()
    }

    func selectChannel(_ id: String?) async {
        guard id != selectedChannelID else { return }
        selectedChannelID = id
        await loadAll()
    }

    private func loadAll() async {
        guard let client else { return }
        isLoading = true
        errorMessage = nil
        if versionString.isEmpty {
            versionString = (try? await client.fetchShopwareVersion()) ?? ""
        }
        do {
            async let m = client.dashboardMetrics(salesChannelID: selectedChannelID)
            async let ob = client.fetchHistory(paid: false, range: trendRange, salesChannelID: selectedChannelID)
            async let rb = client.fetchHistory(paid: true, range: trendRange, salesChannelID: selectedChannelID)
            async let ls = client.fetchLowStockProducts(salesChannelID: selectedChannelID)
            async let tp = client.fetchTopProducts(since: DateRange.days30.sinceDate, salesChannelID: selectedChannelID)
            async let lang = client.fetchLanguageBreakdown(since: DateRange.days30.sinceDate, salesChannelID: selectedChannelID)
            metrics = try await m
            orderBuckets = try await ob
            revenueBuckets = try await rb
            lowStockProducts = (try? await ls) ?? []
            topProducts = (try? await tp) ?? []
            languageStats = (try? await lang) ?? []
        } catch {
            if !error.isCancellation {
                errorMessage = error.shopwareDisplayMessage
            }
        }
        isLoading = false
    }

    func fetchOrdersHistory() async {
        guard let client else { return }
        isLoading = true
        errorMessage = nil
        do { orderBuckets = try await client.fetchHistory(paid: false, range: ordersRange, salesChannelID: selectedChannelID) }
        catch {
            if !error.isCancellation {
                errorMessage = error.shopwareDisplayMessage
            }
        }
        isLoading = false
    }

    func fetchRevenueHistory() async {
        guard let client else { return }
        isLoading = true
        errorMessage = nil
        do { revenueBuckets = try await client.fetchHistory(paid: true, range: revenueRange, salesChannelID: selectedChannelID) }
        catch {
            if !error.isCancellation {
                errorMessage = error.shopwareDisplayMessage
            }
        }
        isLoading = false
    }

    func fetchTrendHistory() async {
        ordersRange = trendRange
        revenueRange = trendRange
        guard let client else { return }
        isLoading = true
        errorMessage = nil
        do {
            async let orders = client.fetchHistory(
                paid: false,
                range: trendRange,
                salesChannelID: selectedChannelID
            )
            async let revenue = client.fetchHistory(
                paid: true,
                range: trendRange,
                salesChannelID: selectedChannelID
            )
            orderBuckets = try await orders
            revenueBuckets = try await revenue
        } catch {
            if !error.isCancellation {
                errorMessage = error.shopwareDisplayMessage
            }
        }
        isLoading = false
    }

    func dismissAttentionItem(_ id: String) {
        dismissedAttentionIDs.insert(id)
    }

    func setStock(productID: String, to nextStock: Int) async {
        guard let client,
              let index = lowStockProducts.firstIndex(where: { $0.id == productID })
        else { return }
        let previous = lowStockProducts[index].stock
        lowStockProducts[index].stock = max(0, nextStock)
        errorMessage = nil
        do {
            try await client.updateProduct(id: productID, stock: max(0, nextStock))
            if nextStock > 10 {
                lowStockProducts.removeAll { $0.id == productID }
            }
        } catch {
            if let rollback = lowStockProducts.firstIndex(where: { $0.id == productID }) {
                lowStockProducts[rollback].stock = previous
            }
            errorMessage = error.shopwareDisplayMessage
        }
    }

    /// Toggle maintenance for a sales channel and update the live channel list.
    func setMaintenance(channelID: String, enabled: Bool) async throws {
        guard let client else { throw ShopwareAPIError.message("Not connected.") }
        try await client.setMaintenance(salesChannelID: channelID, enabled: enabled)
        if let index = salesChannels.firstIndex(where: { $0.id == channelID }) {
            salesChannels[index].maintenance = enabled
        }
    }

    /// Sign out of every shop and return to the connect screen.
    func disconnect() async {
        try? credentialStore.clear()
        savedConnections = []
        resetActiveShop()
    }

    // MARK: - Active-shop helpers

    /// Point the dashboard at `next`, clearing the previous shop's loaded data
    /// so nothing stale flashes during the switch.
    private func activate(_ next: ShopwareConnection, client: ShopwareAdminClient) {
        self.client = client
        connection = next
        clearLoadedData()
    }

    /// Clear the active shop entirely (no shop selected).
    private func resetActiveShop() {
        connection = nil
        client = nil
        isAddingShop = false
        clearLoadedData()
    }

    /// Reset all per-shop dashboard data and selections.
    private func clearLoadedData() {
        metrics = nil
        orderBuckets = []
        revenueBuckets = []
        salesChannels = []
        selectedChannelID = nil
        lowStockProducts = []
        topProducts = []
        languageStats = []
        dismissedAttentionIDs = []
        versionString = ""
        errorMessage = nil
    }
}
