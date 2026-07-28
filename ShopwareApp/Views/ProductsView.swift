import SwiftUI

struct ProductsView: View {
    enum StockFilter: String, CaseIterable, Identifiable {
        case all = "ALL"
        case low = "LOW STOCK"
        case out = "OUT OF STOCK"
        var id: String { rawValue }
    }

    @ObservedObject var viewModel: ProductsViewModel
    @State private var searchText = ""
    @State private var products: [ProductSummary] = []
    @State private var filter: StockFilter = .all
    @State private var isLoading = false
    @State private var busyProductIDs: Set<String> = []
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    private var filteredProducts: [ProductSummary] {
        products.filter {
            switch filter {
            case .all: return true
            case .low: return $0.stock <= 10
            case .out: return $0.stock == 0
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Products")
                        .industryKicker(11)
                        .foregroundStyle(Color.industryText)
                    Spacer()
                    Text("\(filteredProducts.count) items")
                        .font(IndustryFont.display(15))
                        .foregroundStyle(Color.industryFaint)
                }

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(Color.industryFaint)
                    TextField("Name or product number", text: $searchText)
                        .font(IndustryFont.body(15))
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Color.industrySurface)
                .overlay(Rectangle().stroke(Color.industryLine, lineWidth: 1))

                filterControl

                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                }

                if isLoading && products.isEmpty {
                    Text("LOADING…")
                        .industryKicker()
                        .foregroundStyle(Color.industryFaint)
                        .frame(maxWidth: .infinity)
                        .padding(30)
                } else if filteredProducts.isEmpty {
                    Text("Nothing matches that search.")
                        .font(IndustryFont.body(14))
                        .foregroundStyle(Color.industryDim)
                        .frame(maxWidth: .infinity)
                        .padding(30)
                } else {
                    productList
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Color.industryBackground)
        .navigationTitle("")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: searchText) { term in scheduleSearch(term: term) }
        .task {
            if products.isEmpty { await runSearch(term: "") }
        }
    }

    private var filterControl: some View {
        HStack(spacing: 6) {
            ForEach(StockFilter.allCases) { candidate in
                Button {
                    filter = candidate
                } label: {
                    Text(candidate.rawValue)
                        .industryKicker(9.5)
                        .foregroundStyle(filter == candidate ? Color.industryInverse : Color.industryDim)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .background(filter == candidate ? Color.industryAccent : Color.clear)
                        .overlay(Rectangle().stroke(Color.industryHair, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var productList: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.industryLine).frame(height: 1)
            ForEach(filteredProducts) { product in
                HStack(spacing: 12) {
                    NavigationLink {
                        ProductEditView(viewModel: viewModel, productID: product.id) {
                            Task { await runSearch(term: searchText) }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            ProductThumbnail(url: product.coverURL, size: 40)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(product.name)
                                    .font(IndustryFont.body(14, medium: true))
                                    .foregroundStyle(Color.industryText)
                                    .lineLimit(1)
                                Text(productMeta(product))
                                    .industryKicker()
                                    .foregroundStyle(Color.industryFaint)
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
                Rectangle().fill(Color.industryHair).frame(height: 1)
            }
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
            await runSearch(term: term)
        }
    }

    private func runSearch(term: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let results = try await viewModel.searchProducts(term: term)
            guard !Task.isCancelled else { return }
            products = results
        } catch {
            if !error.isCancellation {
                errorMessage = error.shopwareDisplayMessage
            }
        }
        isLoading = false
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
                Color.industrySunk
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .overlay(Rectangle().stroke(Color.industryHair, lineWidth: 1))
    }
}
