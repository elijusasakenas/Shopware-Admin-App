//
//  Customer.swift
//  ShopwareApp
//
//  Customer registration model (account vs. guest).
//

import Foundation

struct CustomerRegistration: Identifiable {
    var id: String
    var name: String
    var email: String
    var createdAt: Date?
    var guest: Bool
}
