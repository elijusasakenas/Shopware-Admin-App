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
                            .font(.subheadline)
                            .foregroundStyle(Color.secondaryText)
                        HStack(alignment: .top) {
                            Text(order.amountTotal.formatted(.currency(code: order.currencyCode)))
                                .font(.system(size: 40, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.primaryText)
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                            Spacer()
                            if !customerName.isEmpty || !customerEmail.isEmpty {
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text("Customer").font(.caption).foregroundStyle(Color.secondaryText)
                                    Text(customerName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.primaryText)
                                    Text(customerEmail)
                                        .font(.caption)
                                        .foregroundStyle(Color.secondaryText)
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
        .background(Color.appBackground)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("ORDER \(order.orderNumber)")
                    .font(.headline)
                    .foregroundStyle(Color.primaryText)
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
            Divider()
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
        .shopwareCard()
    }

    private func stageRow(
        number: String,
        title: LocalizedStringKey,
        state: String,
        transitions: [OrderTransition],
        onSelect: @escaping (OrderTransition) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.shopwareBlue)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(Color.secondaryText)
                Text(StateLocalization.stateName(state))
                    .font(.headline)
                    .foregroundStyle(Color.primaryText)
                    .contentTransition(.numericText())
            }
            Spacer()
            if transitions.isEmpty {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(Color.shopwareBlue)
                    .frame(width: 44, height: 44)
            } else if transitions.count == 1, let transition = transitions.first {
                Button { onSelect(transition) } label: {
                    Text("MARK \(StateLocalization.transitionName(transition.targetStateTechnicalName))")
                        .font(.caption.weight(.semibold))
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
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .foregroundStyle(Color.inverseText)
                        .background(Color.shopwareBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .disabled(isTransitioning)
                .opacity(isTransitioning ? 0.45 : 1)
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.border.opacity(0.55)).frame(height: 1)
        }
    }

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Items")
                .padding(.bottom, 10)
            Divider()
            if isLoading {
                Text("LOADING…")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(22)
            } else {
                ForEach(lineItems) { item in
                    HStack(spacing: 12) {
                        Text("\(item.quantity)×")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.shopwareBlue)
                            .frame(width: 26, alignment: .leading)
                        Text(item.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primaryText)
                        Spacer()
                        Text(item.totalPrice.formatted(.currency(code: order.currencyCode)))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primaryText)
                    }
                    .padding(.vertical, 11)
                    Divider()
                }
                HStack {
                    Text("Total incl. VAT").font(.caption).foregroundStyle(Color.secondaryText)
                    Spacer()
                    Text(order.amountTotal.formatted(.currency(code: order.currencyCode)))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.primaryText)
                }
                .padding(.top, 12)
            }
        }
        .shopwareCard()
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
