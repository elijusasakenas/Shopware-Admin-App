import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: ShopwareDashboardViewModel
    @State private var showAssistant = false
    @State private var showProducts = false
    @State private var assistantDraft = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ShopHeaderView(viewModel: viewModel)
                    .riseIn(0)

                if viewModel.isChannelPickerExpanded {
                    channelPicker
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .riseIn(0.06)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        if let message = viewModel.errorMessage {
                            ErrorBanner(message: message)
                        }
                        heroPlate.riseIn(0.12)
                        attentionSection.riseIn(0.18)
                        trendSection.riseIn(0.24)
                        ordersSection.riseIn(0.30)
                        stockSection.riseIn(0.34)
                        alsoSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                }
                .refreshable { await viewModel.refresh() }

                AskBar(draft: $assistantDraft) {
                    showAssistant = true
                }
            }
            .background(Color.industryBackground)
            .task { await viewModel.refresh() }
            .navigationDestination(for: LatestOrder.self) { order in
                if let client = viewModel.apiClient {
                    OrderDetailView(
                        viewModel: OrderDetailViewModel(client: client) {
                            await viewModel.refresh()
                        },
                        order: order
                    )
                }
            }
            .navigationDestination(isPresented: $showAssistant) {
                AIChatScreen(viewModel: viewModel, initialDraft: assistantDraft)
            }
            .onChange(of: showAssistant) { isShowing in
                if !isShowing {
                    assistantDraft = ""
                }
            }
            .navigationDestination(isPresented: $showProducts) {
                productsDestination
            }
            #if !os(macOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
    }

    private var channelPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sales channel")
                .industryKicker()
                .foregroundStyle(Color.industryFaint)
                .padding(.bottom, 10)
            channelRow(id: nil, name: "All sales channels", share: "100%")
            ForEach(Array(viewModel.salesChannels.enumerated()), id: \.element.id) { index, channel in
                channelRow(
                    id: channel.id,
                    name: channel.name,
                    share: viewModel.salesChannels.count == 2 ? (index == 0 ? "78%" : "22%") : "—"
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(Color.industrySunk)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.industryHair).frame(height: 1)
        }
    }

    private func channelRow(id: String?, name: String, share: String) -> some View {
        Button {
            Task {
                await viewModel.selectChannel(id)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    viewModel.isChannelPickerExpanded = false
                }
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Rectangle().stroke(Color.industryAccent, lineWidth: 1).frame(width: 9, height: 9)
                    if viewModel.selectedChannelID == id {
                        Rectangle().fill(Color.industryAccent).frame(width: 5, height: 5)
                    }
                }
                Text(name)
                    .font(IndustryFont.body(15))
                    .foregroundStyle(Color.industryText)
                    .lineLimit(1)
                Spacer()
                Text(share)
                    .font(IndustryFont.display(15))
                    .foregroundStyle(Color.industryDim)
            }
            .frame(minHeight: 44)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.industryHair).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var heroPlate: some View {
        BlueprintFrame {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Turnover · Today")
                        .industryKicker()
                        .foregroundStyle(Color.industryFaint)
                    Spacer()
                    Text(comparisonText)
                        .industryKicker()
                        .foregroundStyle(Color.industryAccent)
                }
                HStack(alignment: .bottom, spacing: 12) {
                    Text(viewModel.metrics?.todayRevenue.formatted(
                        .currency(code: currency).precision(.fractionLength(2))
                    ) ?? "—")
                        .font(IndustryFont.display(50))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .foregroundStyle(Color.industryText)
                        .contentTransition(.numericText())
                    HeroSparkline(buckets: viewModel.revenueBuckets)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                Rectangle().fill(Color.industryHair).frame(height: 1)
                HStack(spacing: 0) {
                    satellite("Orders", value: viewModel.metrics?.orderCountToday.formatted() ?? "—")
                    divider
                    satellite("Avg. basket", value: averageBasket)
                    divider
                    satellite("Customers", value: viewModel.metrics?.customerCount.formatted() ?? "—")
                }
            }
        }
    }

    private var comparisonText: String {
        guard viewModel.revenueBuckets.count > 1,
              let latest = viewModel.revenueBuckets.last?.amount
        else { return "LIVE" }
        let previous = viewModel.revenueBuckets.dropLast().last?.amount ?? 0
        guard previous > 0 else { return "LIVE" }
        return String(format: "%+.0f%% VS. PREV.", ((latest - previous) / previous) * 100)
    }

    private var averageBasket: String {
        guard let metrics = viewModel.metrics, metrics.orderCountToday > 0 else { return "—" }
        let average = metrics.todayRevenue / Decimal(metrics.orderCountToday)
        return average.formatted(.currency(code: currency).precision(.fractionLength(2)))
    }

    private func satellite(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).industryKicker(9).foregroundStyle(Color.industryFaint)
            Text(value)
                .font(IndustryFont.display(22))
                .foregroundStyle(Color.industryText)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    private var divider: some View {
        Rectangle().fill(Color.industryHair).frame(width: 1, height: 42)
    }

    private var attentionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Needs you")
                    .font(IndustryFont.display(20))
                    .foregroundStyle(Color.industryText)
                Text(viewModel.attentionItems.count.formatted())
                    .font(IndustryFont.display(20))
                    .foregroundStyle(Color.industryAccent)
                Spacer()
                Text("Ranked by cost of waiting")
                    .industryKicker()
                    .foregroundStyle(Color.industryFaint)
            }
            Rectangle().fill(Color.industryLine).frame(height: 1)
            if viewModel.attentionItems.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(Color.industryAccent)
                    Text("Nothing waiting on you. Queue is clear.")
                        .font(IndustryFont.body(14.5))
                        .foregroundStyle(Color.industryDim)
                }
                .padding(.vertical, 22)
            } else {
                ForEach(viewModel.attentionItems) { item in
                    attentionRow(item)
                    Rectangle().fill(Color.industryHair).frame(height: 1)
                }
            }
        }
    }

    private func attentionRow(_ item: AttentionItem) -> some View {
        HStack(spacing: 12) {
            SeverityLadder(level: item.severity)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(IndustryFont.body(14.5, medium: true))
                    .foregroundStyle(Color.industryText)
                    .lineLimit(2)
                Text(item.meta)
                    .industryKicker()
                    .foregroundStyle(Color.industryFaint)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            attentionAction(item)
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func attentionAction(_ item: AttentionItem) -> some View {
        switch item.destination {
        case .order(let order):
            NavigationLink(value: order) {
                attentionActionLabel(item.action)
            }
            .buttonStyle(IndustryActionButtonStyle())
        case .products:
            Button { showProducts = true } label: {
                attentionActionLabel(item.action)
            }
            .buttonStyle(IndustryActionButtonStyle())
        case .resolve:
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    viewModel.dismissAttentionItem(item.id)
                }
            } label: {
                attentionActionLabel(item.action)
            }
            .buttonStyle(IndustryActionButtonStyle())
        }
    }

    private func attentionActionLabel(_ label: String) -> some View {
        Text(AppLocalization.string(String.LocalizationValue(label)))
            .industryKicker(10.5)
            .padding(.horizontal, 14)
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Trend", detail: viewModel.trendRange.subtitle.uppercased())
            metricControl
            rangeControl
            BlueprintFrame(padding: 14) {
                VStack(spacing: 12) {
                    IndustryTrendChart(
                        buckets: trendBuckets,
                        metric: viewModel.trendMetric,
                        range: viewModel.trendRange,
                        currency: currency
                    )
                    .frame(height: 170)
                    Rectangle().fill(Color.industryHair).frame(height: 1)
                    trendStats
                }
                .opacity(viewModel.isLoading ? 0.45 : 1)
            }
        }
    }

    private var metricControl: some View {
        HStack(spacing: 0) {
            ForEach(TrendMetric.allCases) { metric in
                Button {
                    viewModel.trendMetric = metric
                } label: {
                    Text(metric.label)
                        .industryKicker(10)
                        .foregroundStyle(viewModel.trendMetric == metric ? Color.industryInverse : Color.industryDim)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(viewModel.trendMetric == metric ? Color.industryAccent : Color.clear)
                }
                .buttonStyle(.plain)
                if metric != TrendMetric.allCases.last {
                    Rectangle().fill(Color.industryHair).frame(width: 1, height: 40)
                }
            }
        }
        .overlay(Rectangle().stroke(Color.industryLine, lineWidth: 1))
    }

    private var rangeControl: some View {
        HStack(spacing: 6) {
            ForEach(DateRange.allCases, id: \.self) { range in
                Button {
                    viewModel.trendRange = range
                    Task { await viewModel.fetchTrendHistory() }
                } label: {
                    Text(range.menuLabel)
                        .font(IndustryFont.display(13))
                        .foregroundStyle(viewModel.trendRange == range ? Color.industryAccent : Color.industryDim)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(viewModel.trendRange == range ? Color.industryAccentTint : Color.clear)
                        .overlay(Rectangle().stroke(Color.industryHair, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var trendBuckets: [DashboardBucket] {
        viewModel.trendMetric == .orders ? viewModel.orderBuckets : viewModel.revenueBuckets
    }

    private var trendValues: [Double] {
        trendBuckets.map {
            switch viewModel.trendMetric {
            case .orders: return Double($0.count)
            case .turnover: return $0.amount
            case .basket: return $0.count == 0 ? 0 : $0.amount / Double($0.count)
            }
        }
    }

    private var trendStats: some View {
        let total = trendValues.reduce(0, +)
        let perDay = trendValues.isEmpty ? 0 : total / Double(trendValues.count)
        let best = trendValues.max() ?? 0
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                statCell("Total", value: formatTrend(total))
                Rectangle().fill(Color.industryHair).frame(width: 1, height: 43)
                statCell("Per day", value: formatTrend(perDay))
            }
            Rectangle().fill(Color.industryHair).frame(height: 1)
            HStack(spacing: 0) {
                statCell("Best day", value: formatTrend(best))
                Rectangle().fill(Color.industryHair).frame(width: 1, height: 43)
                statCell("Vs. prev.", value: comparisonText, accent: true)
            }
        }
    }

    private func statCell(_ title: LocalizedStringKey, value: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).industryKicker(9).foregroundStyle(Color.industryFaint)
            Text(value)
                .font(IndustryFont.display(19))
                .foregroundStyle(accent ? Color.industryAccent : Color.industryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
    }

    private func formatTrend(_ value: Double) -> String {
        viewModel.trendMetric == .orders
            ? Int(value).formatted()
            : value.formatted(.currency(code: currency).precision(.fractionLength(0)))
    }

    private var ordersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Orders today", detail: "ALL ORDERS →")
            OrderList(
                orders: viewModel.metrics?.latestOrders ?? [],
                isLoading: viewModel.isLoading
            )
        }
    }

    private var stockSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { showProducts = true } label: {
                SectionHeader(title: "Stock", detail: "ALL PRODUCTS →")
            }
            .buttonStyle(.plain)
            Rectangle().fill(Color.industryLine).frame(height: 1)
            if viewModel.lowStockProducts.isEmpty {
                Text("NO LOW-STOCK PRODUCTS")
                    .industryKicker()
                    .foregroundStyle(Color.industryFaint)
                    .frame(maxWidth: .infinity)
                    .padding(22)
            } else {
                ForEach(viewModel.lowStockProducts) { product in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(product.name)
                                .font(IndustryFont.body(14, medium: true))
                                .foregroundStyle(Color.industryText)
                                .lineLimit(1)
                            Text(product.productNumber.isEmpty ? "PRODUCT" : product.productNumber)
                                .industryKicker()
                                .foregroundStyle(Color.industryFaint)
                        }
                        Spacer()
                        StockStepper(stock: product.stock) { stock in
                            Task { await viewModel.setStock(productID: product.id, to: stock) }
                        }
                    }
                    .padding(.vertical, 10)
                    Rectangle().fill(Color.industryHair).frame(height: 1)
                }
            }
        }
    }

    private var alsoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Also in this shop")
                .industryKicker()
                .foregroundStyle(Color.industryFaint)
                .padding(.bottom, 10)
            Rectangle().fill(Color.industryLine).frame(height: 1)
            alsoRow("Sales by language", value: "\(viewModel.languageStats.count) MARKETS")
            alsoRow("Promotions", value: "MANAGE")
            alsoRow("Newsletter signups", value: "VIEW")
            alsoRow("Shop status & log", value: "ALL GREEN", accent: true)
        }
    }

    @ViewBuilder
    private func alsoRow(_ label: LocalizedStringKey, value: String, accent: Bool = false) -> some View {
        if let client = viewModel.apiClient {
            NavigationLink {
                ShopSettingsView(
                    session: viewModel,
                    settings: ShopSettingsViewModel(client: client)
                )
            } label: {
                alsoRowLabel(label, value: value, accent: accent)
            }
            .buttonStyle(.plain)
        } else {
            alsoRowLabel(label, value: value, accent: accent)
        }
    }

    private func alsoRowLabel(_ label: LocalizedStringKey, value: String, accent: Bool) -> some View {
        HStack {
            Text(label)
                .font(IndustryFont.body(14))
                .foregroundStyle(Color.industryText)
            Spacer()
            Text(value)
                .industryKicker()
                .foregroundStyle(accent ? Color.industryAccent : Color.industryDim)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .light))
                .foregroundStyle(Color.industryFaint)
        }
        .frame(minHeight: 46)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.industryHair).frame(height: 1)
        }
    }

    @ViewBuilder
    private var productsDestination: some View {
        if let client = viewModel.apiClient {
            ProductsView(
                viewModel: ProductsViewModel(
                    client: client,
                    salesChannelID: viewModel.selectedChannelID,
                    currencyCode: currency
                )
            )
        }
    }

    private var currency: String {
        viewModel.metrics?.currencyCode ?? "EUR"
    }
}
