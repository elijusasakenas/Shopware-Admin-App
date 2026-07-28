//
//  Order.swift
//  ShopwareApp
//
//  Order, line item, and state-machine transition models.
//

import Foundation

struct LatestOrder: Identifiable, Equatable, Hashable {
    var id: String
    var orderNumber: String
    var amountTotal: Decimal
    var orderDateTime: Date?
    var currencyCode: String
    /// Language-neutral state key (e.g. "open"); localized at display time.
    var state: String

    var displayDate: String {
        guard let orderDateTime else { return "No date" }
        return orderDateTime.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(AppLocalization.locale)
        )
    }
}

struct OrderLineItem: Identifiable {
    var id: String
    var label: String
    var quantity: Int
    var totalPrice: Decimal
}

struct OrderTransition: Identifiable {
    var id: String { actionName }
    /// The action to POST to the state machine (e.g. "process", "cancel").
    var actionName: String
    /// Language-neutral technicalName of the resulting state; localized for display.
    var targetStateTechnicalName: String
}
