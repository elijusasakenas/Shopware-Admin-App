import SwiftUI

struct PromotionsView: View {
    @ObservedObject var settings: ShopSettingsViewModel
    @State private var promotions: [Promotion] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                }
                promotionsCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .background(Color.appBackground)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Promotions")
                    .font(.headline)
                    .foregroundStyle(Color.primaryText)
            }
        }
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
        .refreshable { await load() }
    }

    private var promotionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Promotions")
                .padding(.bottom, 10)
            Divider()
            if isLoading {
                loadingRow
            } else if promotions.isEmpty {
                emptyRow("NO PROMOTIONS")
            } else {
                ForEach(promotions) { promotion in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(promotion.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.primaryText)
                            if let code = promotion.code, !code.isEmpty {
                                Text("CODE \(code)")
                                    .font(.caption)
                                    .foregroundStyle(Color.secondaryText)
                            }
                        }
                        Spacer()
                        Text(promotion.active ? "ACTIVE" : "PAUSED")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(
                                promotion.active ? Color.shopwareBlue : Color.secondaryText
                            )
                        SquareToggle(isOn: promotionBinding(for: promotion))
                    }
                    .frame(minHeight: 56)
                    if promotion.id != promotions.last?.id {
                        Divider()
                    }
                }
            }
        }
        .shopwareCard()
    }

    private var loadingRow: some View {
        Text("LOADING…")
            .font(.subheadline)
            .foregroundStyle(Color.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(20)
    }

    private func emptyRow(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(20)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            promotions = try await settings.promotions()
        } catch {
            errorMessage = error.shopwareDisplayMessage
        }
        isLoading = false
    }

    private func promotionBinding(for promotion: Promotion) -> Binding<Bool> {
        Binding(
            get: { promotions.first { $0.id == promotion.id }?.active ?? false },
            set: { enabled in
                Task {
                    do {
                        try await settings.setPromotionActive(
                            promotionID: promotion.id,
                            active: enabled
                        )
                        if let index = promotions.firstIndex(where: { $0.id == promotion.id }) {
                            promotions[index].active = enabled
                        }
                    } catch {
                        errorMessage = error.shopwareDisplayMessage
                    }
                }
            }
        )
    }
}

struct NewsletterSignupsView: View {
    @ObservedObject var settings: ShopSettingsViewModel
    @State private var recipients: [NewsletterRecipient] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                }
                newsletterCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .background(Color.appBackground)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Newsletter signups")
                    .font(.headline)
                    .foregroundStyle(Color.primaryText)
            }
        }
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
        .refreshable { await load() }
    }

    private var newsletterCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Newsletter signups")
                .padding(.bottom, 10)
            Divider()
            if isLoading {
                loadingRow
            } else if recipients.isEmpty {
                emptyRow("NO NEWSLETTER REGISTRATIONS")
            } else {
                ForEach(recipients) { recipient in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(recipient.email)
                                .font(.subheadline)
                                .foregroundStyle(Color.primaryText)
                                .lineLimit(1)
                            if let createdAt = recipient.createdAt {
                                Text(
                                    createdAt.formatted(
                                        Date.FormatStyle(date: .abbreviated, time: .shortened)
                                            .locale(AppLocalization.locale)
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(Color.secondaryText)
                            }
                        }
                        Spacer()
                        Text(recipient.statusLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.shopwareBlue)
                    }
                    .padding(.vertical, 10)
                    if recipient.id != recipients.last?.id {
                        Divider()
                    }
                }
            }
        }
        .shopwareCard()
    }

    private var loadingRow: some View {
        Text("LOADING…")
            .font(.subheadline)
            .foregroundStyle(Color.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(20)
    }

    private func emptyRow(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(20)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            recipients = try await settings.newsletterRecipients()
        } catch {
            errorMessage = error.shopwareDisplayMessage
        }
        isLoading = false
    }
}

struct RecentOrdersView: View {
    let client: ShopwareAdminClient
    var salesChannelID: String?
    var onRefresh: () async -> Void

    @State private var orders: [LatestOrder] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                }
                OrderList(orders: orders, isLoading: isLoading, emptyMessage: "No orders yet.")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .background(Color.appBackground)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Orders")
                    .font(.headline)
                    .foregroundStyle(Color.primaryText)
            }
        }
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
        .refreshable {
            await load()
            await onRefresh()
        }
        .navigationDestination(for: LatestOrder.self) { order in
            OrderDetailView(
                viewModel: OrderDetailViewModel(client: client) {
                    await onRefresh()
                },
                order: order
            )
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            var payload: [String: Any] = [
                "limit": 50,
                "sort": [["field": "orderDateTime", "order": "DESC"]],
                "associations": ["currency": [:], "stateMachineState": [:]]
            ]
            if let salesChannelID {
                payload["filter"] = [
                    ["type": "equals", "field": "salesChannelId", "value": salesChannelID]
                ]
            }
            orders = try await client.searchOrders(payload)
        } catch {
            errorMessage = error.shopwareDisplayMessage
        }
        isLoading = false
    }
}

struct LanguageStatsView: View {
    @ObservedObject var session: ShopwareDashboardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                languageCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .background(Color.appBackground)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Sales by language")
                    .font(.headline)
                    .foregroundStyle(Color.primaryText)
            }
        }
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Sales by language · 30d")
                .padding(.bottom, 10)
            Divider()
            if session.languageStats.isEmpty {
                Text("No orders in this period")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(20)
            } else {
                let maximum = max(session.languageStats.map(\.count).max() ?? 1, 1)
                ForEach(Array(session.languageStats.enumerated()), id: \.element.id) { index, stat in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(stat.name)
                                .font(.subheadline)
                                .foregroundStyle(Color.primaryText)
                            Spacer()
                            Text("\(stat.count) ORDERS")
                                .font(.caption)
                                .foregroundStyle(Color.secondaryText)
                            Text(stat.amount.formatted(
                                .currency(code: session.metrics?.currencyCode ?? "EUR")
                                    .precision(.fractionLength(0))
                            ))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primaryText)
                        }
                        TickBar(fraction: Double(stat.count) / Double(maximum))
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) {
                        if index < session.languageStats.count - 1 {
                            Rectangle().fill(Color.border.opacity(0.55)).frame(height: 1)
                        }
                    }
                }
            }
        }
        .shopwareCard()
    }
}

/// Payment methods offered at checkout, with an on/off switch per method.
/// Turning a method off hides it from customers in every sales channel.
struct PaymentMethodsView: View {
    @ObservedObject var settings: ShopSettingsViewModel
    /// The dashboard's selected sales channel, used to flag methods it does not offer.
    var selectedChannelID: String?
    var selectedChannelName: String?
    /// All sales channels, to name the ones a change would leave without payment.
    var salesChannels: [SalesChannel] = []

    @State private var methods: [PaymentMethod] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var busyIDs: Set<String> = []
    /// A switch-off waiting for confirmation, with the channels it would leave without payment.
    @State private var pendingDisable: (method: PaymentMethod, channelIDs: [String])?

    private var activeCount: Int { methods.filter(\.active).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                }
                methodsCard
                Text("Turning a method off hides it at checkout in every sales channel. Orders already placed are not changed.")
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .background(Color.appBackground)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Payment methods")
                    .font(.headline)
                    .foregroundStyle(Color.primaryText)
            }
        }
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
        .refreshable { await load() }
        .alert(
            "Turn off this payment method?",
            isPresented: Binding(
                get: { pendingDisable != nil },
                set: { if !$0 { pendingDisable = nil } }
            ),
            presenting: pendingDisable
        ) { pending in
            Button("Turn off", role: .destructive) { setActive(pending.method, false) }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(String(
                format: AppLocalization.string("No other active payment method is offered in %@. Customers there will not be able to complete an order."),
                channelNames(pending.channelIDs)
            ))
        }
    }

    private var methodsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Payment methods")
                Spacer()
                if !methods.isEmpty {
                    Text(String(
                        format: AppLocalization.string("%lld methods · %lld active"),
                        methods.count, activeCount
                    ))
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText)
                }
            }
            .padding(.bottom, 10)
            Divider()
            if isLoading && methods.isEmpty {
                Text("LOADING…")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(20)
            } else if methods.isEmpty {
                Text("NO PAYMENT METHODS")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(20)
            } else {
                ForEach(methods) { method in
                    row(method)
                    if method.id != methods.last?.id {
                        Divider()
                    }
                }
            }
        }
        .shopwareCard()
    }

    private func row(_ method: PaymentMethod) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(method.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primaryText)
                HStack(spacing: 6) {
                    if let flow = flowLabel(method.flow) {
                        Text(flow)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.secondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.controlBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    Text(channelText(method))
                        .font(.caption)
                        .foregroundStyle(isMissingInSelectedChannel(method) ? Color.amber : Color.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer()
            if busyIDs.contains(method.id) {
                ProgressView().tint(.shopwareBlue)
            }
            Text(method.active ? "ACTIVE" : "OFF")
                .font(.caption.weight(.semibold))
                .foregroundStyle(method.active ? Color.shopwareBlue : Color.secondaryText)
            SquareToggle(isOn: binding(for: method))
                .disabled(busyIDs.contains(method.id))
        }
        .frame(minHeight: 60)
    }

    private func flowLabel(_ flow: PaymentMethod.Flow) -> String? {
        switch flow {
        case .direct: return AppLocalization.string("DIRECT")
        case .redirect: return AppLocalization.string("REDIRECT")
        case .unknown: return nil
        }
    }

    private func isMissingInSelectedChannel(_ method: PaymentMethod) -> Bool {
        guard let selectedChannelID else { return false }
        return !method.salesChannelIDs.contains(selectedChannelID)
    }

    private func channelText(_ method: PaymentMethod) -> String {
        if isMissingInSelectedChannel(method), let selectedChannelName {
            return String(format: AppLocalization.string("Not offered in %@"), selectedChannelName)
        }
        switch method.salesChannelIDs.count {
        case 0: return AppLocalization.string("No sales channel")
        case 1: return AppLocalization.string("1 sales channel")
        default: return String(format: AppLocalization.string("%lld sales channels"), method.salesChannelIDs.count)
        }
    }

    private func binding(for method: PaymentMethod) -> Binding<Bool> {
        Binding(
            get: { methods.first { $0.id == method.id }?.active ?? false },
            set: { enabled in
                let stranded = enabled ? [] : ShopSettingsViewModel.channelsLeftWithoutPayment(
                    turningOff: method.id, in: methods
                )
                if !stranded.isEmpty {
                    pendingDisable = (method, stranded)
                } else {
                    setActive(method, enabled)
                }
            }
        )
    }

    private func channelNames(_ ids: [String]) -> String {
        let names = ids.map { id in salesChannels.first { $0.id == id }?.name ?? id }
        return ListFormatter.localizedString(byJoining: names)
    }

    private func setActive(_ method: PaymentMethod, _ enabled: Bool) {
        busyIDs.insert(method.id)
        errorMessage = nil
        Task {
            do {
                try await settings.setPaymentMethodActive(paymentMethodID: method.id, active: enabled)
                if let index = methods.firstIndex(where: { $0.id == method.id }) {
                    methods[index].active = enabled
                }
            } catch {
                errorMessage = error.shopwareDisplayMessage
            }
            busyIDs.remove(method.id)
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            methods = try await settings.paymentMethods()
        } catch {
            errorMessage = error.shopwareDisplayMessage
        }
        isLoading = false
    }
}
