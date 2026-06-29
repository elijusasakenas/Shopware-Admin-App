//
//  ProductsView.swift
//  ShopwareApp
//
//  Searchable product list: queries /api/search/product by name or product
//  number, scoped to the dashboard's selected sales channel.
//

import SwiftUI

struct ProductsView: View {
    @ObservedObject var viewModel: ShopwareDashboardViewModel

    @State private var searchText = ""
    @State private var products: [ProductSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    /// Bumped on each keystroke so the debounce task can cancel a stale search.
    @State private var searchTask: Task<Void, Never>?
    /// The product whose edit sheet is currently presented, if any.
    @State private var editingProduct: ProductSummary?

    private var currencyCode: String { viewModel.metrics?.currencyCode ?? "EUR" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                }

                if isLoading && products.isEmpty {
                    ProgressView()
                        .tint(.shopwareBlue)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if products.isEmpty {
                    Text(searchText.isEmpty ? "No products found." : "No products match “\(searchText)”.")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else {
                    VStack(spacing: 0) {
                        ForEach(products) { product in
                            Button {
                                editingProduct = product
                            } label: {
                                ProductRow(product: product, currencyCode: currencyCode)
                            }
                            .buttonStyle(.plain)
                            if product.id != products.last?.id {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.border, lineWidth: 1))
                }
            }
            .padding(20)
            .padding(.bottom, 32)
        }
        .background(Color.appBackground)
        .navigationTitle("Products")
        .searchable(text: $searchText, prompt: "Search by name or number")
        .onChange(of: searchText) { newValue in
            scheduleSearch(term: newValue)
        }
        .task {
            // Initial population (most-recent products) before any typing.
            if products.isEmpty { await runSearch(term: "") }
        }
        .sheet(item: $editingProduct) { product in
            ProductEditView(viewModel: viewModel, productID: product.id) {
                // Re-run the current search so the list reflects the saved edits.
                Task { await runSearch(term: searchText) }
            }
            .appAppearance()
        }
    }

    /// Debounce keystrokes so we don't fire a request on every character.
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

private struct ProductRow: View {
    let product: ProductSummary
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            ProductThumbnail(url: product.coverURL, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(product.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(1)
                if !product.productNumber.isEmpty {
                    Text(product.productNumber)
                        .font(.caption)
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if let price = product.price {
                    Text(price.formatted(.currency(code: currencyCode)))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.primaryText)
                }
                stockBadge
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.secondaryText)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var stockBadge: some View {
        let isOut = product.stock == 0
        Text(isOut ? "Out of stock" : "\(product.stock) in stock")
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isOut ? Color.red.opacity(0.12) : Color.shopwareBlue.opacity(0.12))
            .foregroundStyle(isOut ? Color.red : Color.shopwareBlue)
            .clipShape(Capsule())
    }
}

/// Square product cover thumbnail with a placeholder fallback.
struct ProductThumbnail: View {
    let url: URL?
    var size: CGFloat = 44

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                ZStack {
                    Color.appBackground
                    Image(systemName: "shippingbox")
                        .foregroundStyle(Color.secondaryText)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.border, lineWidth: 1))
    }
}
