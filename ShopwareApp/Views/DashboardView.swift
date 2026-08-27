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

                GeometryReader { geometry in
                    ScrollView(.vertical) {
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
                        .frame(width: geometry.size.width, alignment: .leading)
                    }
                    .frame(width: geometry.size.width)
                    .clipped()
                    .refreshable { await viewModel.refresh() }
                }

                AskBar(draft: $assistantDraft) {
                    showAssistant = true
                }
            }
            .background(Color.appBackground)
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
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.secondaryText)
                .padding(.bottom, 10)
            channelRow(id: nil, name: "All sales channels", share: viewModel.channelShareLabel(for: nil))
            ForEach(viewModel.salesChannels) { channel in
                channelRow(
                    id: channel.id,
                    name: channel.name,
                    share: viewModel.channelShareLabel(for: channel.id)
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(Color.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.border.opacity(0.7)).frame(height: 1)
        }
    }

    private func channelRow(id: String?, name: String, share: String) -> some View {
        let selected = viewModel.selectedChannelID == id
        return Button {
            Task {
                await viewModel.selectChannel(id)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    viewModel.isChannelPickerExpanded = false
                }
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Color.shopwareBlue, lineWidth: 1.5).frame(width: 12, height: 12)
                    if selected {
                        Circle().fill(Color.shopwareBlue).frame(width: 6, height: 6)
                    }
                }
                Text(name)
                    .font(.body.weight(selected ? .semibold : .regular))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(1)
                Spacer()
                Text(share)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selected ? Color.shopwareBlue : Color.secondaryText)
            }
            .padding(.horizontal, 4)
            .frame(minHeight: 48)
            .background(selected ? Color.shopwareBlue.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .top) {
                Rectangle().fill(Color.border.opacity(0.55)).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var heroPlate: some View {
        BlueprintFrame {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Turnover · Today")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.secondaryText)
                    Spacer()
                    Text(comparisonText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.shopwareBlue)
                }
                HStack(alignment: .bottom, spacing: 12) {
                    Text(viewModel.metrics?.todayRevenue.formatted(
                        .currency(code: currency).precision(.fractionLength(2))
                    ) ?? "—")
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .foregroundStyle(Color.primaryText)
                        .contentTransition(.numericText())
                    HeroSparkline(buckets: viewModel.revenueBuckets)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                Divider()
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
        guard let change = TrendComparison.dayOverDayPercent(buckets: viewModel.revenueBuckets) else {
            return "LIVE"
        }
        return "\(String(format: "%+.0f", change))% \(AppLocalization.string("VS. YDAY"))"
    }

    private var periodComparisonText: String {
        guard let change = TrendComparison.halfOverHalfPercent(trendValues) else { return "—" }
        return String(format: "%+.0f%%", change)
    }

    private var averageBasket: String {
        guard let metrics = viewModel.metrics, metrics.orderCountToday > 0 else { return "—" }
        let average = metrics.todayRevenue / Decimal(metrics.orderCountToday)
        return average.formatted(.currency(code: currency).precision(.fractionLength(2)))
    }

    private func satellite(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Color.secondaryText)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    private var divider: some View {
        Divider().frame(height: 42)
    }

    private var attentionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Things to review")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.primaryText)
                Text(viewModel.attentionItems.count.formatted())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.shopwareBlue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.shopwareBlue.opacity(0.10))
                    .clipShape(Capsule())
                Spacer()
            }
            Text("Take a look when you have a moment.")
                .font(.subheadline)
                .foregroundStyle(Color.secondaryText)
            Divider()
            if viewModel.attentionItems.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(Color.shopwareBlue)
                    Text("Nothing waiting on you. Queue is clear.")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondaryText)
                }
                .padding(.vertical, 22)
            } else {
                ForEach(viewModel.attentionItems) { item in
                    attentionRow(item)
                    if item.id != viewModel.attentionItems.last?.id {
                        Divider()
                    }
                }
            }
        }
        .shopwareCard()
    }

    private func attentionRow(_ item: AttentionItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            attentionIcon(item)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.meta)
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText)
                    .lineLimit(1)
                attentionAction(item)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
    }

    private func attentionIcon(_ item: AttentionItem) -> some View {
        let presentation = attentionIconPresentation(item)
        return Image(systemName: presentation.symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(presentation.color)
            .frame(width: 38, height: 38)
            .background(presentation.color.opacity(0.11))
            .clipShape(Circle())
            .accessibilityHidden(true)
    }

    private func attentionIconPresentation(
        _ item: AttentionItem
    ) -> (symbol: String, color: Color) {
        switch item.destination {
        case .order:
            return ("doc.text", .shopwareBlue)
        case .products:
            return ("shippingbox.fill", item.severity >= 3 ? .red : .amber)
        case .resolve:
            return ("checkmark", .green)
        }
    }

    @ViewBuilder
    private func attentionAction(_ item: AttentionItem) -> some View {
        switch item.destination {
        case .order(let order):
            NavigationLink(value: order) {
                attentionActionLabel(item.action)
            }
            .buttonStyle(.plain)
        case .products:
            Button { showProducts = true } label: {
                attentionActionLabel(item.action)
            }
            .buttonStyle(.plain)
        case .resolve:
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    viewModel.dismissAttentionItem(item.id)
                }
            } label: {
                attentionActionLabel(item.action)
            }
            .buttonStyle(.plain)
        }
    }

    private func attentionActionLabel(_ label: String) -> some View {
        HStack(spacing: 6) {
            Text(AppLocalization.string(String.LocalizationValue(label)))
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.shopwareBlue)
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .background(Color.shopwareBlue.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                    Divider()
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(viewModel.trendMetric == metric ? Color.inverseText : Color.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(viewModel.trendMetric == metric ? Color.shopwareBlue : Color.clear)
                }
                .buttonStyle(.plain)
                if metric != TrendMetric.allCases.last {
                    Divider().frame(height: 40)
                }
            }
        }
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.border, lineWidth: 1)
        )
    }

    private var rangeControl: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(DateRange.allCases, id: \.self) { range in
                    Button {
                        viewModel.trendRange = range
                        Task { await viewModel.fetchTrendHistory() }
                    } label: {
                        Text(range.menuLabel)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(
                                viewModel.trendRange == range
                                    ? Color.shopwareBlue
                                    : Color.secondaryText
                            )
                            .padding(.horizontal, 10)
                            .frame(minHeight: 32)
                            .background(
                                viewModel.trendRange == range
                                    ? Color.shopwareBlue.opacity(0.10)
                                    : Color.surface
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
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
                Divider().frame(height: 43)
                statCell("Per day", value: formatTrend(perDay))
            }
            Divider()
            HStack(spacing: 0) {
                statCell("Best day", value: formatTrend(best))
                Divider().frame(height: 43)
                statCell("Vs. prev.", value: periodComparisonText, accent: true)
            }
        }
    }

    private func statCell(_ title: LocalizedStringKey, value: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(Color.secondaryText)
            Text(value)
                .font(.headline)
                .foregroundStyle(accent ? Color.shopwareBlue : Color.primaryText)
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
            if let client = viewModel.apiClient {
                NavigationLink {
                    RecentOrdersView(
                        client: client,
                        salesChannelID: viewModel.selectedChannelID,
                        onRefresh: { await viewModel.refresh() }
                    )
                } label: {
                    SectionHeader(title: "Orders today", detail: "ALL ORDERS →")
                }
                .buttonStyle(.plain)
            } else {
                SectionHeader(title: "Orders today", detail: "ALL ORDERS →")
            }
            OrderList(
                orders: viewModel.metrics?.todayOrders ?? [],
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
            Divider()
            if viewModel.lowStockProducts.isEmpty {
                Text("No low-stock products")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(22)
            } else {
                ForEach(viewModel.lowStockProducts) { product in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(product.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.primaryText)
                                .lineLimit(1)
                            Text(product.productNumber.isEmpty ? "PRODUCT" : product.productNumber)
                                .font(.caption)
                                .foregroundStyle(Color.secondaryText)
                        }
                        Spacer()
                        StockStepper(stock: product.stock) { stock in
                            Task { await viewModel.setStock(productID: product.id, to: stock) }
                        }
                    }
                    .padding(.vertical, 10)
                    if product.id != viewModel.lowStockProducts.last?.id {
                        Divider()
                    }
                }
            }
        }
        .shopwareCard()
    }

    private var alsoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Also in this shop")
                .font(.headline)
                .foregroundStyle(Color.primaryText)
                .padding(.bottom, 10)
            Divider()
            alsoRow("Sales by language", value: "\(viewModel.languageStats.count) MARKETS", destination: .languages)
            alsoRow("Promotions", value: "MANAGE", destination: .promotions)
            alsoRow("Newsletter signups", value: "VIEW", destination: .newsletter)
            alsoRow(
                "Shop status & log",
                value: viewModel.shopStatusLabel,
                accent: viewModel.hasMaintenanceChannel,
                destination: .shopStatus,
                isLast: true
            )
        }
        .shopwareCard()
    }

    @ViewBuilder
    private func alsoRow(
        _ label: LocalizedStringKey,
        value: String,
        accent: Bool = false,
        destination: ShopShortcutDestination = .settings,
        isLast: Bool = false
    ) -> some View {
        if let client = viewModel.apiClient {
            NavigationLink {
                shortcutDestination(destination, client: client)
            } label: {
                alsoRowLabel(label, value: value, accent: accent, isLast: isLast)
            }
            .buttonStyle(.plain)
        } else {
            alsoRowLabel(label, value: value, accent: accent, isLast: isLast)
        }
    }

    @ViewBuilder
    private func shortcutDestination(
        _ destination: ShopShortcutDestination,
        client: ShopwareAdminClient
    ) -> some View {
        let settings = ShopSettingsViewModel(client: client)
        switch destination {
        case .settings:
            ShopSettingsView(session: viewModel, settings: settings)
        case .promotions:
            PromotionsView(settings: settings)
        case .newsletter:
            NewsletterSignupsView(settings: settings)
        case .shopStatus:
            ShopStatusView(settings: settings)
        case .languages:
            LanguageStatsView(session: viewModel)
        }
    }

    private func alsoRowLabel(_ label: LocalizedStringKey, value: String, accent: Bool, isLast: Bool) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.primaryText)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent ? Color.shopwareBlue : Color.secondaryText)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.secondaryText)
        }
        .frame(minHeight: 48)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Color.border.opacity(0.55)).frame(height: 1)
            }
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

private enum ShopShortcutDestination {
    case settings
    case promotions
    case newsletter
    case shopStatus
    case languages
}
