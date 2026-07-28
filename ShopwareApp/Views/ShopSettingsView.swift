import SwiftUI

struct ShopSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: ShopwareDashboardViewModel
    @ObservedObject var settings: ShopSettingsViewModel
    @AppStorage(AppLanguage.storageKey) private var appLanguageCode = AppLanguage.system.rawValue
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue

    @State private var promotions: [Promotion] = []
    @State private var recipients: [NewsletterRecipient] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var confirmSignOut = false
    @State private var showShopSwitcher = false
    @State private var closeSettingsAfterSwitch = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 26) {
                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                }
                appearanceSection
                manageSection
                AIAssistantSettingsCard()
                maintenanceSection
                promotionsSection
                languageSection
                newsletterSection
                signOutButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 34)
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .background(Color.appBackground)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("SHOP & APP")
                    .font(.headline)
                    .foregroundStyle(Color.primaryText)
            }
        }
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
        .confirmationDialog(
            "Sign out of all shops?",
            isPresented: $confirmSignOut,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) {
                Task { await session.disconnect() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showShopSwitcher, onDismiss: {
            guard closeSettingsAfterSwitch else { return }
            closeSettingsAfterSwitch = false
            dismiss()
        }) {
            ShopSwitcherSheet(session: session) {
                closeSettingsAfterSwitch = true
                showShopSwitcher = false
            }
            .appAppearance()
            #if os(macOS)
            .frame(minWidth: 420, idealWidth: 460, minHeight: 360, idealHeight: 440)
            #else
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
            #endif
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Appearance")
            HStack(spacing: 0) {
                appearanceButton(.light)
                Divider().frame(height: 44)
                appearanceButton(.dark)
            }
            .background(Color.controlBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack {
                Text("App language")
                    .font(.body)
                    .foregroundStyle(Color.primaryText)
                Spacer()
                Picker("App language", selection: $appLanguageCode) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                }
                .labelsHidden()
                .tint(Color.shopwareBlue)
            }
            .frame(minHeight: 48)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.border.opacity(0.55)).frame(height: 1)
            }
        }
        .shopwareCard()
    }

    private func appearanceButton(_ option: AppAppearance) -> some View {
        Button {
            appearance = option.rawValue
        } label: {
            Text(option.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(appearance == option.rawValue ? Color.inverseText : Color.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(appearance == option.rawValue ? Color.shopwareBlue : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private var manageSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Manage")
                .padding(.bottom, 10)
            Divider()
            NavigationLink {
                NewCustomersView(settings: settings)
            } label: {
                manageRow("New customer registrations", value: "+18 / 7D")
            }
            .buttonStyle(.plain)
            NavigationLink {
                ShopStatusView(settings: settings)
            } label: {
                manageRow("Shop status & log", value: "ALL GREEN")
            }
            .buttonStyle(.plain)
            Button {
                showShopSwitcher = true
            } label: {
                manageRow(
                    "Switch shop",
                    value: session.connection?.displayName ?? "—",
                    localizeValue: false
                )
            }
            .buttonStyle(.plain)
            .disabled(session.savedConnections.count < 2)
            .opacity(session.savedConnections.count < 2 ? 0.45 : 1)
            Button {
                session.beginAddingShop()
            } label: {
                manageRow(
                    "Add another shop",
                    value: AppLocalization.string("\(session.savedConnections.count) CONNECTED")
                )
            }
            .buttonStyle(.plain)
        }
        .shopwareCard()
    }

    private func manageRow(
        _ title: LocalizedStringKey,
        value: String,
        localizeValue: Bool = true
    ) -> some View {
        HStack {
            Text(title)
                .font(.body)
                .foregroundStyle(Color.primaryText)
            Spacer()
            Group {
                if localizeValue {
                    Text(AppLocalization.string(String.LocalizationValue(value)))
                } else {
                    Text(value)
                }
            }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.secondaryText)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .light))
                .foregroundStyle(Color.secondaryText)
        }
        .frame(minHeight: 50)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.border.opacity(0.55)).frame(height: 1)
        }
    }

    private var maintenanceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Maintenance mode")
                .padding(.bottom, 10)
            Divider()
            ForEach(session.salesChannels) { channel in
                HStack {
                    Text(channel.name)
                        .font(.body)
                        .foregroundStyle(Color.primaryText)
                    Spacer()
                    Text(channel.maintenance ? "ON" : "OFF")
                        .font(.caption)
                        .foregroundStyle(Color.secondaryText)
                    SquareToggle(isOn: maintenanceBinding(for: channel))
                }
                .frame(minHeight: 52)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.border.opacity(0.55)).frame(height: 1)
                }
            }
        }
        .shopwareCard()
    }

    private var promotionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Promotions")
                .padding(.bottom, 10)
            Divider()
            if isLoading {
                loadingRow
            } else if promotions.isEmpty {
                emptyRow("NO PROMOTIONS")
            } else {
                ForEach(promotions.prefix(10)) { promotion in
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
                            .foregroundStyle(promotion.active ? Color.shopwareBlue : Color.secondaryText)
                        SquareToggle(isOn: promotionBinding(for: promotion))
                    }
                    .frame(minHeight: 56)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.border.opacity(0.55)).frame(height: 1)
                    }
                }
            }
        }
        .shopwareCard()
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Sales by language · 30d")
                .padding(.bottom, 10)
            Divider()
            let maximum = max(session.languageStats.map(\.count).max() ?? 1, 1)
            ForEach(session.languageStats) { stat in
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
                    Rectangle().fill(Color.border.opacity(0.55)).frame(height: 1)
                }
            }
        }
        .shopwareCard()
    }

    private var newsletterSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Newsletter signups")
                .padding(.bottom, 10)
            Divider()
            if isLoading {
                loadingRow
            } else if recipients.isEmpty {
                emptyRow("NO NEWSLETTER REGISTRATIONS")
            } else {
                ForEach(recipients.prefix(10)) { recipient in
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
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.border.opacity(0.55)).frame(height: 1)
                    }
                }
            }
        }
        .shopwareCard()
    }

    private var signOutButton: some View {
        Button {
            confirmSignOut = true
        } label: {
            Text("SIGN OUT OF ALL SHOPS")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.red)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
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
        do {
            async let loadedPromotions = settings.promotions()
            async let loadedRecipients = settings.newsletterRecipients()
            promotions = try await loadedPromotions
            recipients = try await loadedRecipients
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

    private func maintenanceBinding(for channel: SalesChannel) -> Binding<Bool> {
        Binding(
            get: {
                session.salesChannels.first { $0.id == channel.id }?.maintenance ?? false
            },
            set: { enabled in
                Task {
                    do {
                        try await session.setMaintenance(
                            channelID: channel.id,
                            enabled: enabled
                        )
                    } catch {
                        errorMessage = error.shopwareDisplayMessage
                    }
                }
            }
        )
    }
}

private struct ShopSwitcherSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: ShopwareDashboardViewModel
    let onSwitched: () -> Void

    @State private var switchingShopID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView(.vertical) {
                LazyVStack(spacing: 10) {
                    ForEach(session.savedConnections) { shop in
                        shopRow(shop)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .clipped()
        }
        .frame(maxWidth: .infinity)
        .background(Color.appBackground)
        .interactiveDismissDisabled(switchingShopID != nil)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Switch shop")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.primaryText)
                Text("Choose a saved shop")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryText)
            }

            Spacer(minLength: 12)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.primaryText)
                    .frame(width: 34, height: 34)
                    .background(Color.controlBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.border, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(switchingShopID != nil)
            .accessibilityLabel("Cancel")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Color.surface)
    }

    private func shopRow(_ shop: ShopwareConnection) -> some View {
        let isActive = shop.id == session.connection?.id
        let isSwitching = switchingShopID == shop.id

        return Button {
            guard !isActive, switchingShopID == nil else { return }
            switchingShopID = shop.id
            Task {
                await session.switchTo(shop)
                switchingShopID = nil
                onSwitched()
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "storefront")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isActive ? Color.inverseText : Color.shopwareBlue)
                    .frame(width: 42, height: 42)
                    .background(isActive ? Color.shopwareBlue : Color.shopwareBlue.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(shop.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(shop.displayHost)
                        .font(.caption)
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                Spacer(minLength: 8)

                if isSwitching {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.shopwareBlue)
                } else if isActive {
                    Label("Active", systemImage: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.shopwareBlue)
                        .labelStyle(.titleAndIcon)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.secondaryText)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .background(isActive ? Color.shopwareBlue.opacity(0.08) : Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isActive ? Color.shopwareBlue.opacity(0.55) : Color.border,
                        lineWidth: 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isActive || switchingShopID != nil)
        .opacity(switchingShopID != nil && !isSwitching ? 0.6 : 1)
        .accessibilityHint(isActive ? Text("Active") : Text("Switch shop"))
    }
}
