//
//  OrderDetailView.swift
//  ShopwareApp
//
//  Single order: header, customer, line items, and live state-machine
//  transitions for order / payment / delivery status.
//

import SwiftUI

struct OrderDetailView: View {
    @ObservedObject var viewModel: ShopwareDashboardViewModel
    let order: LatestOrder

    @State private var lineItems: [OrderLineItem] = []
    @State private var customerName = ""
    @State private var customerEmail = ""
    @State private var orderState: String
    @State private var orderTransitions: [OrderTransition] = []
    @State private var transactionID: String?
    @State private var paymentState = ""
    @State private var paymentTransitions: [OrderTransition] = []
    @State private var deliveryID: String?
    @State private var deliveryState = ""
    @State private var deliveryTransitions: [OrderTransition] = []
    @State private var isLoading = true
    @State private var isTransitioning = false
    @State private var errorMessage: String?

    init(viewModel: ShopwareDashboardViewModel, order: LatestOrder) {
        self.viewModel = viewModel
        self.order = order
        _orderState = State(initialValue: order.state)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Order header
                VStack(alignment: .leading, spacing: 8) {
                    Text(order.orderNumber)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Color.primaryText)
                    Text(order.displayDate)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondaryText)
                    HStack {
                        Text(StateLocalization.stateName(orderState))
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.shopwareBlue.opacity(0.12))
                            .foregroundStyle(Color.shopwareBlue)
                            .clipShape(Capsule())
                        Spacer()
                        Text(order.amountTotal.formatted(.currency(code: order.currencyCode)))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.primaryText)
                    }
                }

                if let errorMessage { ErrorBanner(message: errorMessage) }

                // Customer
                if !customerName.isEmpty || !customerEmail.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Customer")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.primaryText)
                        if !customerName.isEmpty {
                            Text(customerName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.primaryText)
                        }
                        if !customerEmail.isEmpty {
                            Text(customerEmail)
                                .font(.subheadline)
                                .foregroundStyle(Color.secondaryText)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.border, lineWidth: 1))
                }

                // Line items
                VStack(alignment: .leading, spacing: 8) {
                    Text("Items")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.primaryText)
                    if isLoading {
                        ProgressView().tint(.shopwareBlue).frame(maxWidth: .infinity).padding(12)
                    } else if lineItems.isEmpty {
                        Text("No items found.")
                            .font(.subheadline)
                            .foregroundStyle(Color.secondaryText)
                    } else {
                        ForEach(lineItems) { item in
                            HStack(spacing: 12) {
                                Text("\(item.quantity)×")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Color.shopwareBlue)
                                Text(item.label)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.primaryText)
                                Spacer()
                                Text(item.totalPrice.formatted(.currency(code: order.currencyCode)))
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Color.primaryText)
                            }
                            .padding(.vertical, 6)
                            if item.id != lineItems.last?.id { Divider() }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.border, lineWidth: 1))

                // Status management
                StateTransitionCard(
                    title: "Order status",
                    currentState: orderState,
                    transitions: orderTransitions,
                    isBusy: isTransitioning
                ) { transition in
                    Task { await perform(entityName: "order", entityID: order.id, transition: transition) }
                }

                if let transactionID, !paymentState.isEmpty {
                    StateTransitionCard(
                        title: "Payment status",
                        currentState: paymentState,
                        transitions: paymentTransitions,
                        isBusy: isTransitioning
                    ) { transition in
                        Task { await perform(entityName: "order_transaction", entityID: transactionID, transition: transition) }
                    }
                }

                if let deliveryID, !deliveryState.isEmpty {
                    StateTransitionCard(
                        title: "Delivery status",
                        currentState: deliveryState,
                        transitions: deliveryTransitions,
                        isBusy: isTransitioning
                    ) { transition in
                        Task { await perform(entityName: "order_delivery", entityID: deliveryID, transition: transition) }
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 32)
        }
        .background(Color.appBackground)
        .navigationTitle("Order")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
    }

    private func load() async {
        do {
            lineItems = try await viewModel.orderLineItems(orderID: order.id)
            if let customer = try await viewModel.orderCustomer(orderID: order.id) {
                customerName = customer.name
                customerEmail = customer.email
            }
            orderTransitions = try await viewModel.stateTransitions(entityName: "order", entityID: order.id)

            if let transaction = try await viewModel.orderTransaction(orderID: order.id) {
                transactionID = transaction.id
                paymentState = transaction.state
                paymentTransitions = try await viewModel.stateTransitions(entityName: "order_transaction", entityID: transaction.id)
            }
            if let delivery = try await viewModel.orderDelivery(orderID: order.id) {
                deliveryID = delivery.id
                deliveryState = delivery.state
                deliveryTransitions = try await viewModel.stateTransitions(entityName: "order_delivery", entityID: delivery.id)
            }
        } catch {
            errorMessage = error.shopwareDisplayMessage
        }
        isLoading = false
    }

    private func perform(entityName: String, entityID: String, transition: OrderTransition) async {
        isTransitioning = true
        errorMessage = nil
        do {
            try await viewModel.performTransition(entityName: entityName, entityID: entityID, action: transition.actionName)
            switch entityName {
            case "order":
                orderState = transition.targetStateTechnicalName
                orderTransitions = (try? await viewModel.stateTransitions(entityName: entityName, entityID: entityID)) ?? []
            case "order_transaction":
                paymentState = transition.targetStateTechnicalName
                paymentTransitions = (try? await viewModel.stateTransitions(entityName: entityName, entityID: entityID)) ?? []
            case "order_delivery":
                deliveryState = transition.targetStateTechnicalName
                deliveryTransitions = (try? await viewModel.stateTransitions(entityName: entityName, entityID: entityID)) ?? []
            default:
                break
            }
            await viewModel.refresh()
        } catch {
            errorMessage = error.shopwareDisplayMessage
        }
        isTransitioning = false
    }
}

struct StateTransitionCard: View {
    let title: LocalizedStringKey
    /// Language-neutral technicalName of the current state; localized here.
    let currentState: String
    let transitions: [OrderTransition]
    let isBusy: Bool
    let onSelect: (OrderTransition) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.secondaryText)
                    .textCase(.uppercase)
                Text(StateLocalization.stateName(currentState))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.primaryText)
            }
            Spacer()
            if isBusy {
                ProgressView().tint(.shopwareBlue)
            } else if !transitions.isEmpty {
                Menu {
                    ForEach(transitions) { transition in
                        Button(StateLocalization.transitionName(transition.targetStateTechnicalName)) { onSelect(transition) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Change")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.inverseText)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
                    .background(Color.shopwareBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.border, lineWidth: 1))
    }
}
