//
//  AccessToken.swift
//  ShopwareApp
//
//  Cached OAuth client-credentials token with its expiry.
//

import Foundation

struct AccessToken {
    var value: String
    var expiresAt: Date
}
