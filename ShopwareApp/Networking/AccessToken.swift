//
//  AccessToken.swift
//  ShopwareApp
//
//  Cached OAuth client-credentials token with its expiry.
//

import Foundation

struct AccessToken: Sendable {
    var value: String
    var expiresAt: Date
}
