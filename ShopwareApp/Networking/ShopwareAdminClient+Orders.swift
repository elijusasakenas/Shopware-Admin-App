//
//  ShopwareAdminClient+Orders.swift
//  ShopwareApp
//
//  Order detail, line items, and state-machine transitions.
//

import Foundation

extension ShopwareAdminClient {
    func fetchOrderLineItems(orderID: String) async throws -> [OrderLineItem] {
        let response = try await requestJSON(path: "/api/search/order-line-item", method: "POST", body: [
            "limit": 100,
            "filter": [["type": "equals", "field": "orderId", "value": orderID]],
            "sort": [["field": "position", "order": "ASC"]]
        ])
        return (response["data"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            let attrs = entityAttributes(of: row)
            return OrderLineItem(
                id: id,
                label: attrs["label"] as? String ?? "Item",
                quantity: attrs["quantity"] as? Int ?? 0,
                totalPrice: decimal(from: attrs["totalPrice"])
            )
        }
    }

    func fetchOrderCustomer(orderID: String) async throws -> (name: String, email: String)? {
        let response = try await requestJSON(path: "/api/search/order-customer", method: "POST", body: [
            "limit": 1,
            "filter": [["type": "equals", "field": "orderId", "value": orderID]]
        ])
        guard let row = (response["data"] as? [[String: Any]])?.first else { return nil }
        let attrs = entityAttributes(of: row)
        let first = attrs["firstName"] as? String ?? ""
        let last = attrs["lastName"] as? String ?? ""
        return (name: "\(first) \(last)".trimmingCharacters(in: .whitespaces),
                email: attrs["email"] as? String ?? "")
    }

    // entityName: "order", "order_transaction" or "order_delivery"
    func fetchStateTransitions(entityName: String, entityID: String) async throws -> [OrderTransition] {
        let response = try await requestJSON(path: "/api/_action/state-machine/\(entityName)/\(entityID)/state", method: "GET")
        return (response["transitions"] as? [[String: Any]] ?? []).compactMap { transition in
            guard let action = transition["actionName"] as? String else { return nil }
            // Carry the destination state's language-neutral technicalName so the
            // app localizes the menu label itself (falls back to the action name).
            let toState = transition["toStateMachineState"] as? [String: Any]
            let targetTechnicalName = toState?["technicalName"] as? String ?? action
            return OrderTransition(actionName: action, targetStateTechnicalName: targetTechnicalName)
        }
    }

    func performStateTransition(entityName: String, entityID: String, action: String) async throws {
        _ = try await requestJSON(path: "/api/_action/state-machine/\(entityName)/\(entityID)/state/\(action)", method: "POST")
    }

    // Returns the newest transaction/delivery of an order with its current state name
    func fetchOrderSubEntity(_ entity: String, orderID: String) async throws -> (id: String, state: String)? {
        let response = try await requestJSON(path: "/api/search/\(entity)", method: "POST", body: [
            "limit": 1,
            "filter": [["type": "equals", "field": "orderId", "value": orderID]],
            "sort": [["field": "createdAt", "order": "DESC"]],
            "associations": ["stateMachineState": [:]]
        ])
        guard let row = (response["data"] as? [[String: Any]])?.first,
              let id = row["id"] as? String else { return nil }
        let attrs = entityAttributes(of: row)
        let included = response["included"] as? [[String: Any]] ?? []
        let includedByID = Dictionary(uniqueKeysWithValues: included.compactMap { item -> (String, [String: Any])? in
            guard let itemID = item["id"] as? String else { return nil }
            return (itemID, item)
        })
        let relationships = row["relationships"] as? [String: Any] ?? [:]
        let stateID = relationshipID(from: relationships["stateMachineState"])
        let stateAttrs = includedByID[stateID ?? ""]?["attributes"] as? [String: Any]
        return (id: id, state: orderStateTechnicalName(from: attrs, includedState: stateAttrs))
    }
}
