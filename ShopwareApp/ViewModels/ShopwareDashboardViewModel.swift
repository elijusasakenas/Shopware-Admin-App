//
//  ShopwareDashboardViewModel.swift
//  ShopwareApp
//
//  Observable state for the dashboard: owns the API client and credential
//  store, drives connect/refresh/disconnect, and exposes per-screen reads.
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
    @Published var salesChannels: [SalesChannel] = []
    @Published var selectedChannelID: String?
    @Published var lowStockProducts: [LowStockProduct] = []
    @Published var topProducts: [TopProduct] = []
    @Published var languageStats: [LanguageStat] = []
    @Published var versionString = ""

    var selectedChannelName: String {
        guard let id = selectedChannelID else { return "All sales channels" }
        return salesChannels.first { $0.id == id }?.name ?? "Sales channel"
    }

    private let credentialStore = CredentialStore()
    private var client: ShopwareAdminClient?

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
            async let ob = client.fetchHistory(paid: false, range: ordersRange, salesChannelID: selectedChannelID)
            async let rb = client.fetchHistory(paid: true, range: revenueRange, salesChannelID: selectedChannelID)
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

    func promotions() async throws -> [Promotion] {
        guard let client else { throw ShopwareAPIError.message("Not connected.") }
        return try await client.fetchPromotions()
    }

    func setPromotionActive(promotionID: String, active: Bool) async throws {
        guard let client else { throw ShopwareAPIError.message("Not connected.") }
        try await client.setPromotionActive(promotionID: promotionID, active: active)
    }

    func newsletterRecipients() async throws -> [NewsletterRecipient] {
        guard let client else { throw ShopwareAPIError.message("Not connected.") }
        return try await client.fetchNewsletterRecipients()
    }

    func recentCustomers() async throws -> [CustomerRegistration] {
        guard let client else { throw ShopwareAPIError.message("Not connected.") }
        return try await client.fetchRecentCustomers()
    }

    func logEntries() async throws -> [LogEntry] {
        guard let client else { throw ShopwareAPIError.message("Not connected.") }
        return try await client.fetchLogEntries()
    }

    func domainURLs() async throws -> [String] {
        guard let client else { throw ShopwareAPIError.message("Not connected.") }
        return try await client.fetchDomainURLs()
    }

    func shopwareVersion() async throws -> String {
        guard let client else { throw ShopwareAPIError.message("Not connected.") }
        return try await client.fetchShopwareVersion()
    }

    func setMaintenance(channelID: String, enabled: Bool) async throws {
        guard let client else { throw ShopwareAPIError.message("Not connected.") }
        try await client.setMaintenance(salesChannelID: channelID, enabled: enabled)
        if let index = salesChannels.firstIndex(where: { $0.id == channelID }) {
            salesChannels[index].maintenance = enabled
        }
    }

    /// Search products for the products screen, scoped to the selected channel.
    func searchProducts(term: String) async throws -> [ProductSummary] {
        guard let client else { throw ShopwareAPIError.message("Not connected.") }
        return try await client.searchProducts(term: term, salesChannelID: selectedChannelID)
    }

    /// Languages configured in the shop, for editing product translations.
    func shopLanguages() async throws -> [ShopLanguage] {
        guard let client else { throw ShopwareAPIError.message("Not connected.") }
        return try await client.fetchLanguages()
    }

    /// Load a single product's full editable state, in the given language.
    func productDetail(id: String, languageID: String? = nil) async throws -> ProductDetail {
        guard let client else { throw ShopwareAPIError.message("Not connected.") }
        return try await client.fetchProductDetail(id: id, languageID: languageID)
    }

    /// Save edited product fields. Only non-nil values are written. `languageID`
    /// selects which translation the name is written into.
    func updateProduct(
        id: String,
        name: String? = nil,
        stock: Int? = nil,
        grossPrice: Decimal? = nil,
        taxRate: Decimal? = nil,
        currencyID: String? = nil,
        active: Bool? = nil,
        languageID: String? = nil
    ) async throws {
        guard let client else { throw ShopwareAPIError.message("Not connected.") }
        try await client.updateProduct(
            id: id, name: name, stock: stock, grossPrice: grossPrice,
            taxRate: taxRate, currencyID: currencyID, active: active, languageID: languageID
        )
    }

    /// Load every image attached to a product, for the gallery.
    func productImages(productID: String) async throws -> [ProductImage] {
        guard let client else { throw ShopwareAPIError.message("Not connected.") }
        return try await client.fetchProductImages(productID: productID)
    }

    /// Upload and append an image to a product's gallery.
    func addProductImage(productID: String, imageData: Data, position: Int, setAsCover: Bool) async throws {
        guard let client else { throw ShopwareAPIError.message("Not connected.") }
        try await client.addProductImage(
            productID: productID, imageData: imageData, position: position, setAsCover: setAsCover
        )
    }

    /// Mark an existing product image as the cover.
    func setProductCover(productID: String, productMediaID: String) async throws {
        guard let client else { throw ShopwareAPIError.message("Not connected.") }
        try await client.setProductCover(productID: productID, productMediaID: productMediaID)
    }

    /// Remove an image from a product.
    func deleteProductImage(productMediaID: String) async throws {
        guard let client else { throw ShopwareAPIError.message("Not connected.") }
        try await client.deleteProductImage(productMediaID: productMediaID)
    }

    /// Persist a new gallery order.
    func reorderProductImages(orderedIDs: [String]) async throws {
        guard let client else { throw ShopwareAPIError.message("Not connected.") }
        try await client.reorderProductImages(orderedIDs: orderedIDs)
    }

    func orderLineItems(orderID: String) async throws -> [OrderLineItem] {
        guard let client else { throw ShopwareAPIError.message("Not connected.") }
        return try await client.fetchOrderLineItems(orderID: orderID)
    }

    func orderCustomer(orderID: String) async throws -> (name: String, email: String)? {
        guard let client else { throw ShopwareAPIError.message("Not connected.") }
        return try await client.fetchOrderCustomer(orderID: orderID)
    }

    func stateTransitions(entityName: String, entityID: String) async throws -> [OrderTransition] {
        guard let client else { throw ShopwareAPIError.message("Not connected.") }
        return try await client.fetchStateTransitions(entityName: entityName, entityID: entityID)
    }

    func performTransition(entityName: String, entityID: String, action: String) async throws {
        guard let client else { throw ShopwareAPIError.message("Not connected.") }
        try await client.performStateTransition(entityName: entityName, entityID: entityID, action: action)
    }

    func orderTransaction(orderID: String) async throws -> (id: String, state: String)? {
        guard let client else { throw ShopwareAPIError.message("Not connected.") }
        return try await client.fetchOrderSubEntity("order-transaction", orderID: orderID)
    }

    func orderDelivery(orderID: String) async throws -> (id: String, state: String)? {
        guard let client else { throw ShopwareAPIError.message("Not connected.") }
        return try await client.fetchOrderSubEntity("order-delivery", orderID: orderID)
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
        versionString = ""
        errorMessage = nil
    }
}
