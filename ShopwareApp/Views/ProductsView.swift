import SwiftUI

struct ProductsView: View {
    @ObservedObject var viewModel: ProductsViewModel
    @State private var searchText = ""
    @State private var products: [ProductSummary] = []
    /// Rows matching the current search and filter on the server.
    @State private var totalCount = 0
    /// Active main products in the shop (or selected channel), shown at the top.
    @State private var activeProductCount: Int?
    @State private var loadedPages = 0
    @State private var filter: ProductStockFilter = .all
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var busyProductIDs: Set<String> = []
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    /// Bumped on every reload so a slow, outdated response cannot overwrite newer results.
    @State private var queryGeneration = 0

    private var hasMore: Bool { products.count < totalCount }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Products")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.primaryText)
                    Spacer()
                    if !products.isEmpty {
                        Text(String(format: AppLocalization.string("Showing %lld of %lld"), products.count, totalCount))
                            .font(.subheadline)
                            .foregroundStyle(Color.secondaryText)
                    }
                }

                activeProductsSummary

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(Color.secondaryText)
                    TextField("Name or product number", text: $searchText)
                        .font(.body)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.border, lineWidth: 1)
                )

                filterControl

                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                }

                if isLoading && products.isEmpty {
                    ProgressView()
                        .tint(.shopwareBlue)
                        .frame(maxWidth: .infinity)
                        .padding(30)
                } else if products.isEmpty {
                    Text("Nothing matches that search.")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(30)
                } else {
                    productList
                    if hasMore {
                        loadMoreButton
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Color.appBackground)
        .navigationTitle("")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onValueChange(of: searchText) { term in scheduleSearch(term: term) }
        .onValueChange(of: filter) { _ in
            searchTask?.cancel()
            Task { await reload() }
        }
        .task {
            if products.isEmpty { await reload() }
            if activeProductCount == nil { await refreshActiveCount() }
        }
    }

    private var activeProductsSummary: some View {
        HStack(spacing: 10) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.shopwareBlue)
            if let activeProductCount {
                Text(String(format: AppLocalization.string("%lld active products in your shop"), activeProductCount))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primaryText)
            } else {
                Text("Counting active products…")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.border, lineWidth: 1)
        )
    }

    private var loadMoreButton: some View {
        Button {
            Task { await loadMore() }
        } label: {
            HStack(spacing: 8) {
                if isLoadingMore {
                    ProgressView().tint(.shopwareBlue)
                }
                Text(String(
                    format: AppLocalization.string("Load more (%lld remaining)"),
                    max(0, totalCount - products.count)
                ))
                .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Color.shopwareBlue)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoadingMore)
    }

    private var filterControl: some View {
        HStack(spacing: 6) {
            ForEach(ProductStockFilter.allCases) { candidate in
                Button {
                    filter = candidate
                } label: {
                    Text(filterTitle(candidate))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(filter == candidate ? Color.inverseText : Color.secondaryText)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .background(filter == candidate ? Color.shopwareBlue : Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var productList: some View {
        VStack(spacing: 0) {
            ForEach(products) { product in
                HStack(spacing: 12) {
                    NavigationLink {
                        ProductEditView(viewModel: viewModel, productID: product.id) {
                            Task {
                                await reload(keepingLoadedRows: true)
                                await refreshActiveCount()
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            ProductThumbnail(url: product.coverURL, size: 40)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(product.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.primaryText)
                                    .lineLimit(1)
                                Text(productMeta(product))
                                    .font(.caption)
                                    .foregroundStyle(Color.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    StockStepper(
                        stock: product.stock,
                        isBusy: busyProductIDs.contains(product.id)
                    ) { next in
                        setStock(productID: product.id, to: next)
                    }
                }
                .padding(.vertical, 10)
                if product.id != products.last?.id {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.border, lineWidth: 1)
        )
    }

    private func filterTitle(_ filter: ProductStockFilter) -> String {
        switch filter {
        case .all: return AppLocalization.string("ALL")
        case .low: return AppLocalization.string("LOW STOCK")
        case .out: return AppLocalization.string("OUT OF STOCK")
        }
    }

    private func productMeta(_ product: ProductSummary) -> String {
        let price = product.price?.formatted(
            .currency(code: viewModel.currencyCode).precision(.fractionLength(2))
        ) ?? "—"
        return "\(product.productNumber) · \(price)"
    }

    private func setStock(productID: String, to stock: Int) {
        guard let index = products.firstIndex(where: { $0.id == productID }) else { return }
        let previous = products[index].stock
        products[index].stock = stock
        busyProductIDs.insert(productID)
        Task {
            do {
                try await viewModel.setStock(productID: productID, to: stock)
            } catch {
                if let rollback = products.firstIndex(where: { $0.id == productID }) {
                    products[rollback].stock = previous
                }
                errorMessage = error.shopwareDisplayMessage
            }
            busyProductIDs.remove(productID)
        }
    }

    private func scheduleSearch(term: String) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await reload(term: term)
        }
    }

    /// Loads the first page again. With `keepingLoadedRows`, reloads as many
    /// rows as are already shown so an edit does not collapse a long list.
    private func reload(term: String? = nil, keepingLoadedRows: Bool = false) async {
        queryGeneration += 1
        let generation = queryGeneration
        let pageSize = ProductsViewModel.pageSize
        let pages = keepingLoadedRows ? max(1, loadedPages) : 1
        isLoading = true
        errorMessage = nil
        do {
            let page = try await viewModel.loadProducts(
                term: term ?? searchText,
                stockFilter: filter,
                page: 1,
                limit: pages * pageSize
            )
            guard generation == queryGeneration, !Task.isCancelled else { return }
            products = page.products
            totalCount = page.total
            loadedPages = pages
        } catch {
            if generation == queryGeneration, !error.isCancellation {
                errorMessage = error.shopwareDisplayMessage
            }
        }
        if generation == queryGeneration { isLoading = false }
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        let generation = queryGeneration
        isLoadingMore = true
        errorMessage = nil
        do {
            let page = try await viewModel.loadProducts(
                term: searchText,
                stockFilter: filter,
                page: loadedPages + 1
            )
            // A new search or filter started meanwhile; this page belongs to the old one.
            guard generation == queryGeneration else { isLoadingMore = false; return }
            products = ProductsViewModel.merge(products, with: page.products)
            totalCount = page.total
            loadedPages += 1
        } catch {
            if !error.isCancellation {
                errorMessage = error.shopwareDisplayMessage
            }
        }
        isLoadingMore = false
    }

    private func refreshActiveCount() async {
        // The count is informational; a failure keeps the previous value
        // instead of covering the list with an error.
        if let count = try? await viewModel.activeProductCount() {
            activeProductCount = count
        }
    }
}

struct ProductThumbnail: View {
    let url: URL?
    var size: CGFloat = 44

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                Color.controlBackground
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.border.opacity(0.7), lineWidth: 1)
        )
    }
}
