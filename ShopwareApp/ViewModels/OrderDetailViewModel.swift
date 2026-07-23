//
//  OrderDetailViewModel.swift
//  ShopwareApp
//
//  Order detail reads and state-machine transitions. Calls `onStateChanged`
//  after a successful transition so the dashboard can refresh KPIs/lists.
//

import Combine
import Foundation

@MainActor
final class OrderDetailViewModel: ObservableObject {
    private let client: ShopwareAdminClient
    private let onStateChanged: () async -> Void

    init(client: ShopwareAdminClient, onStateChanged: @escaping () async -> Void = {}) {
        self.client = client
        self.onStateChanged = onStateChanged
    }

    func orderLineItems(orderID: String) async throws -> [OrderLineItem] {
        try await client.fetchOrderLineItems(orderID: orderID)
    }

    func orderCustomer(orderID: String) async throws -> (name: String, email: String)? {
        try await client.fetchOrderCustomer(orderID: orderID)
    }

    func stateTransitions(entityName: String, entityID: String) async throws -> [OrderTransition] {
        try await client.fetchStateTransitions(entityName: entityName, entityID: entityID)
    }

    func performTransition(entityName: String, entityID: String, action: String) async throws {
        try await client.performStateTransition(entityName: entityName, entityID: entityID, action: action)
        await onStateChanged()
    }

    func orderTransaction(orderID: String) async throws -> (id: String, state: String)? {
        try await client.fetchOrderSubEntity("order-transaction", orderID: orderID)
    }

    func orderDelivery(orderID: String) async throws -> (id: String, state: String)? {
        try await client.fetchOrderSubEntity("order-delivery", orderID: orderID)
    }
}
