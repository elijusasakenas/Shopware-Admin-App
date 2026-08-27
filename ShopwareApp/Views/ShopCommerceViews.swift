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
