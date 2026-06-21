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
    var stock: Int
}

struct TopProduct: Identifiable {
    var id: String { label }
    var label: String
    var quantitySold: Int
}
