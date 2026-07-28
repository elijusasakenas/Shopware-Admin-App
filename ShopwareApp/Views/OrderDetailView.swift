import SwiftUI

struct OrderDetailView: View {
    @ObservedObject var viewModel: OrderDetailViewModel
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

    init(viewModel: OrderDetailViewModel, order: LatestOrder) {
        self.viewModel = viewModel
        self.order = order
        _orderState = State(initialValue: order.state)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                BlueprintFrame {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(order.displayDate)
                            .industryKicker()
                            .foregroundStyle(Color.industryFaint)
                        HStack(alignment: .top) {
                            Text(order.amountTotal.formatted(.currency(code: order.currencyCode)))
                                .font(IndustryFont.display(44))
                                .foregroundStyle(Color.industryText)
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                            Spacer()
                            if !customerName.isEmpty || !customerEmail.isEmpty {
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text("Customer").industryKicker().foregroundStyle(Color.industryFaint)
                                    Text(customerName)
                                        .font(IndustryFont.body(14.5, medium: true))
                                        .foregroundStyle(Color.industryText)
                                    Text(customerEmail)
                                        .font(IndustryFont.body(12.5))
                                        .foregroundStyle(Color.industryDim)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }

                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                }

                progressSection
                itemsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .background(Color.industryBackground)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("ORDER \(order.orderNumber)")
                    .industryKicker(11)
                    .foregroundStyle(Color.industryText)
            }
        }
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Progress")
                .padding(.bottom, 10)
            Rectangle().fill(Color.industryLine).frame(height: 1)
            stageRow(
                number: "01",
                title: "Order status",
                state: orderState,
                transitions: orderTransitions
            ) { transition in
                Task { await perform(entityName: "order", entityID: order.id, transition: transition) }
            }

            if let transactionID, !paymentState.isEmpty {
                stageRow(
                    number: "02",
                    title: "Payment status",
                    state: paymentState,
                    transitions: paymentTransitions
                ) { transition in
                    Task {
                        await perform(
                            entityName: "order_transaction",
                            entityID: transactionID,
                            transition: transition
                        )
                    }
                }
            }

            if let deliveryID, !deliveryState.isEmpty {
                stageRow(
                    number: "03",
                    title: "Delivery status",
                    state: deliveryState,
                    transitions: deliveryTransitions
                ) { transition in
                    Task {
                        await perform(
                            entityName: "order_delivery",
                            entityID: deliveryID,
                            transition: transition
                        )
                    }
                }
            }
        }
    }

    private func stageRow(
        number: String,
        title: String,
        state: String,
        transitions: [OrderTransition],
        onSelect: @escaping (OrderTransition) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(IndustryFont.display(16))
                .foregroundStyle(Color.industryAccent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).industryKicker().foregroundStyle(Color.industryFaint)
                Text(StateLocalization.stateName(state))
                    .font(IndustryFont.display(19))
                    .foregroundStyle(Color.industryText)
                    .contentTransition(.numericText())
            }
            Spacer()
            if transitions.isEmpty {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(Color.industryAccent)
                    .frame(width: 44, height: 44)
            } else if transitions.count == 1, let transition = transitions.first {
                Button { onSelect(transition) } label: {
                    Text("MARK \(StateLocalization.transitionName(transition.targetStateTechnicalName))")
                        .industryKicker(9.5)
                        .padding(.horizontal, 12)
                        .lineLimit(1)
                }
                .buttonStyle(IndustryActionButtonStyle())
                .disabled(isTransitioning)
                .opacity(isTransitioning ? 0.45 : 1)
            } else {
                Menu {
                    ForEach(transitions) { transition in
                        Button(StateLocalization.transitionName(transition.targetStateTechnicalName)) {
                            onSelect(transition)
                        }
                    }
                } label: {
                    Text("CHANGE")
                        .industryKicker(9.5)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .foregroundStyle(Color.industryInverse)
                        .background(Color.industryAccent)
                }
                .disabled(isTransitioning)
                .opacity(isTransitioning ? 0.45 : 1)
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.industryHair).frame(height: 1)
        }
    }

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Items")
                .padding(.bottom, 10)
            Rectangle().fill(Color.industryLine).frame(height: 1)
            if isLoading {
                Text("LOADING…")
                    .industryKicker()
                    .foregroundStyle(Color.industryFaint)
                    .frame(maxWidth: .infinity)
                    .padding(22)
            } else {
                ForEach(lineItems) { item in
                    HStack(spacing: 12) {
                        Text("\(item.quantity)×")
                            .font(IndustryFont.display(16))
                            .foregroundStyle(Color.industryAccent)
                            .frame(width: 26, alignment: .leading)
                        Text(item.label)
                            .font(IndustryFont.body(14, medium: true))
                            .foregroundStyle(Color.industryText)
                        Spacer()
                        Text(item.totalPrice.formatted(.currency(code: order.currencyCode)))
                            .font(IndustryFont.display(16))
                            .foregroundStyle(Color.industryText)
                    }
                    .padding(.vertical, 11)
                    Rectangle().fill(Color.industryHair).frame(height: 1)
                }
                HStack {
                    Text("Total incl. VAT").industryKicker().foregroundStyle(Color.industryFaint)
                    Spacer()
                    Text(order.amountTotal.formatted(.currency(code: order.currencyCode)))
                        .font(IndustryFont.display(22))
                        .foregroundStyle(Color.industryText)
                }
                .padding(.top, 12)
            }
        }
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
                paymentTransitions = try await viewModel.stateTransitions(
                    entityName: "order_transaction",
                    entityID: transaction.id
                )
            }
            if let delivery = try await viewModel.orderDelivery(orderID: order.id) {
                deliveryID = delivery.id
                deliveryState = delivery.state
                deliveryTransitions = try await viewModel.stateTransitions(
                    entityName: "order_delivery",
                    entityID: delivery.id
                )
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
            try await viewModel.performTransition(
                entityName: entityName,
                entityID: entityID,
                action: transition.actionName
            )
            switch entityName {
            case "order":
                orderState = transition.targetStateTechnicalName
                orderTransitions = (try? await viewModel.stateTransitions(
                    entityName: entityName,
                    entityID: entityID
                )) ?? []
            case "order_transaction":
                paymentState = transition.targetStateTechnicalName
                paymentTransitions = (try? await viewModel.stateTransitions(
                    entityName: entityName,
                    entityID: entityID
                )) ?? []
            case "order_delivery":
                deliveryState = transition.targetStateTechnicalName
                deliveryTransitions = (try? await viewModel.stateTransitions(
                    entityName: entityName,
                    entityID: entityID
                )) ?? []
            default:
                break
            }
        } catch {
            errorMessage = error.shopwareDisplayMessage
        }
        isTransitioning = false
    }
}
