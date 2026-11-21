//
//  Product.swift
//  ShopwareApp
//
//  Product models for low-stock alerts and the top-products list.
//

import Foundation

struct LowStockProduct: Identifiable {
    var id: String
    var name: String
    var productNumber: String
    var stock: Int
}

struct TopProduct: Identifiable {
    var id: String { label }
    var label: String
    var quantitySold: Int
}

/// A product row for the searchable products list.
struct ProductSummary: Identifiable {
    var id: String
    var name: String
    var productNumber: String
    var stock: Int
    var active: Bool
    /// Gross price in the product's currency, if available.
    var price: Decimal?
    /// Thumbnail/cover image URL, if the product has a cover.
    var coverURL: URL?
}

/// One page of the products list plus the total number of matching rows, so
/// the list can offer "Load more" until everything is loaded.
struct ProductPage {
    var products: [ProductSummary]
    var total: Int
}

/// Stock filters for the products list. Applied server-side so they cover the
/// whole catalog, not just the rows loaded so far.
enum ProductStockFilter: String, CaseIterable, Identifiable {
    case all
    case low
    case out

    var id: String { rawValue }
    /// Products at or below this stock count as low stock (matches the dashboard).
    static let lowStockThreshold = 10
}

/// Full editable state of a single product, loaded when opening the edit sheet.
struct ProductDetail: Identifiable {
    var id: String
    var name: String
    var productNumber: String
    var stock: Int
    var active: Bool
    var grossPrice: Decimal?
    var netPrice: Decimal?
    /// Currency the price is expressed in; required to write the price back.
    var currencyID: String?
    /// Tax rate as a percentage (e.g. 19 for 19%), used to derive net from gross.
    var taxRate: Decimal?
    var coverURL: URL?
    /// product_media id currently marked as the cover (Shopware `coverId`).
    var coverID: String?
}

/// One image attached to a product (a `product_media` row). `id` is the
/// product_media id (used to set cover/delete/reorder); `mediaId` is the
/// underlying media entity.
struct ProductImage: Identifiable, Equatable {
    var id: String
    var mediaID: String
    var url: URL?
    var position: Int
}

/// Derives the net price from a gross price and a tax rate (as a percentage),
/// matching Shopware's linked gross/net price fields. With no rate, net == gross.
func netFromGross(_ gross: Decimal, taxRate: Decimal?) -> Decimal {
    guard let taxRate, taxRate > 0 else { return gross }
    return gross / (1 + taxRate / 100)
}
