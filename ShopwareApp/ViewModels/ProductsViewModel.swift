//
//  ProductsViewModel.swift
//  ShopwareApp
//
//  Catalog reads/writes for the products list and edit sheet, scoped to the
//  dashboard's selected sales channel.
//

import Combine
import Foundation

@MainActor
final class ProductsViewModel: ObservableObject {
    let currencyCode: String

    private let client: ShopwareAdminClient
    private let salesChannelID: String?

    init(client: ShopwareAdminClient, salesChannelID: String?, currencyCode: String) {
        self.client = client
        self.salesChannelID = salesChannelID
        self.currencyCode = currencyCode
    }

    func searchProducts(term: String) async throws -> [ProductSummary] {
        try await client.searchProducts(term: term, salesChannelID: salesChannelID)
    }

    func productDetail(id: String, languageID: String? = nil) async throws -> ProductDetail {
        try await client.fetchProductDetail(id: id, languageID: languageID)
    }

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
        try await client.updateProduct(
            id: id, name: name, stock: stock, grossPrice: grossPrice,
            taxRate: taxRate, currencyID: currencyID, active: active, languageID: languageID
        )
    }

    func productImages(productID: String) async throws -> [ProductImage] {
        try await client.fetchProductImages(productID: productID)
    }

    func addProductImage(productID: String, imageData: Data, position: Int, setAsCover: Bool) async throws {
        try await client.addProductImage(
            productID: productID, imageData: imageData, position: position, setAsCover: setAsCover
        )
    }

    func setProductCover(productID: String, productMediaID: String) async throws {
        try await client.setProductCover(productID: productID, productMediaID: productMediaID)
    }

    func deleteProductImage(productMediaID: String) async throws {
        try await client.deleteProductImage(productMediaID: productMediaID)
    }

    func reorderProductImages(orderedIDs: [String]) async throws {
        try await client.reorderProductImages(orderedIDs: orderedIDs)
    }
}
