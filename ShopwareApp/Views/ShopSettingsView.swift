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

    var body: some View {
        ScrollView {
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
        .background(Color.industryBackground)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("SHOP & APP")
                    .industryKicker(11)
                    .foregroundStyle(Color.industryText)
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
        .confirmationDialog(
            "Switch shop",
            isPresented: $showShopSwitcher,
            titleVisibility: .visible
        ) {
            ForEach(session.savedConnections) { shop in
                Button {
                    Task {
                        await session.switchTo(shop)
                        dismiss()
                    }
                } label: {
                    if shop.id == session.connection?.id {
                        Label(shop.displayName, systemImage: "checkmark")
                    } else {
                        Text(shop.displayName)
                    }
                }
                .disabled(shop.id == session.connection?.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose a saved shop")
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Appearance")
            HStack(spacing: 0) {
                appearanceButton(.light)
                Rectangle().fill(Color.industryHair).frame(width: 1, height: 44)
                appearanceButton(.dark)
            }
            .overlay(Rectangle().stroke(Color.industryLine, lineWidth: 1))

            HStack {
                Text("App language")
                    .font(IndustryFont.body(14.5))
                    .foregroundStyle(Color.industryText)
                Spacer()
                Picker("App language", selection: $appLanguageCode) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                }
                .labelsHidden()
                .tint(Color.industryAccent)
            }
            .frame(minHeight: 48)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.industryHair).frame(height: 1)
            }
        }
    }

    private func appearanceButton(_ option: AppAppearance) -> some View {
        Button {
            appearance = option.rawValue
        } label: {
            Text(option.title)
                .industryKicker(10)
                .foregroundStyle(appearance == option.rawValue ? Color.industryInverse : Color.industryDim)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(appearance == option.rawValue ? Color.industryAccent : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private var manageSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Manage")
                .padding(.bottom, 10)
            Rectangle().fill(Color.industryLine).frame(height: 1)
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
    }

    private func manageRow(
        _ title: LocalizedStringKey,
        value: String,
        localizeValue: Bool = true
    ) -> some View {
        HStack {
            Text(title)
                .font(IndustryFont.body(14.5))
                .foregroundStyle(Color.industryText)
            Spacer()
            Group {
                if localizeValue {
                    Text(AppLocalization.string(String.LocalizationValue(value)))
                } else {
                    Text(value)
                }
            }
                .industryKicker()
                .foregroundStyle(Color.industryFaint)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .light))
                .foregroundStyle(Color.industryFaint)
        }
        .frame(minHeight: 50)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.industryHair).frame(height: 1)
        }
    }

    private var maintenanceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Maintenance mode")
                .padding(.bottom, 10)
            Rectangle().fill(Color.industryLine).frame(height: 1)
            ForEach(session.salesChannels) { channel in
                HStack {
                    Text(channel.name)
                        .font(IndustryFont.body(14.5))
                        .foregroundStyle(Color.industryText)
                    Spacer()
                    Text(channel.maintenance ? "ON" : "OFF")
                        .industryKicker()
                        .foregroundStyle(Color.industryFaint)
                    SquareToggle(isOn: maintenanceBinding(for: channel))
                }
                .frame(minHeight: 52)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.industryHair).frame(height: 1)
                }
            }
        }
    }

    private var promotionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Promotions")
                .padding(.bottom, 10)
            Rectangle().fill(Color.industryLine).frame(height: 1)
            if isLoading {
                loadingRow
            } else if promotions.isEmpty {
                emptyRow("NO PROMOTIONS")
            } else {
                ForEach(promotions.prefix(10)) { promotion in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(promotion.name)
                                .font(IndustryFont.body(14.5, medium: true))
                                .foregroundStyle(Color.industryText)
                            if let code = promotion.code, !code.isEmpty {
                                Text("CODE \(code)")
                                    .industryKicker()
                                    .foregroundStyle(Color.industryFaint)
                            }
                        }
                        Spacer()
                        Text(promotion.active ? "ACTIVE" : "PAUSED")
                            .industryKicker()
                            .foregroundStyle(promotion.active ? Color.industryAccent : Color.industryFaint)
                        SquareToggle(isOn: promotionBinding(for: promotion))
                    }
                    .frame(minHeight: 56)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.industryHair).frame(height: 1)
                    }
                }
            }
        }
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Sales by language · 30d")
                .padding(.bottom, 10)
            Rectangle().fill(Color.industryLine).frame(height: 1)
            let maximum = max(session.languageStats.map(\.count).max() ?? 1, 1)
            ForEach(session.languageStats) { stat in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(stat.name)
                            .font(IndustryFont.body(14))
                            .foregroundStyle(Color.industryText)
                        Spacer()
                        Text("\(stat.count) ORDERS")
                            .industryKicker()
                            .foregroundStyle(Color.industryFaint)
                        Text(stat.amount.formatted(
                            .currency(code: session.metrics?.currencyCode ?? "EUR")
                                .precision(.fractionLength(0))
                        ))
                        .font(IndustryFont.display(16))
                        .foregroundStyle(Color.industryText)
                    }
                    TickBar(fraction: Double(stat.count) / Double(maximum))
                }
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.industryHair).frame(height: 1)
                }
            }
        }
    }

    private var newsletterSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Newsletter signups")
                .padding(.bottom, 10)
            Rectangle().fill(Color.industryLine).frame(height: 1)
            if isLoading {
                loadingRow
            } else if recipients.isEmpty {
                emptyRow("NO NEWSLETTER REGISTRATIONS")
            } else {
                ForEach(recipients.prefix(10)) { recipient in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(recipient.email)
                                .font(IndustryFont.body(14))
                                .foregroundStyle(Color.industryText)
                                .lineLimit(1)
                            if let createdAt = recipient.createdAt {
                                Text(
                                    createdAt.formatted(
                                        Date.FormatStyle(date: .abbreviated, time: .shortened)
                                            .locale(AppLocalization.locale)
                                    )
                                )
                                    .industryKicker()
                                    .foregroundStyle(Color.industryFaint)
                            }
                        }
                        Spacer()
                        Text(recipient.statusLabel)
                            .industryKicker()
                            .foregroundStyle(Color.industryAccent)
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.industryHair).frame(height: 1)
                    }
                }
            }
        }
    }

    private var signOutButton: some View {
        Button {
            confirmSignOut = true
        } label: {
            Text("SIGN OUT OF ALL SHOPS")
                .industryKicker(10)
                .foregroundStyle(Color.industryDim)
                .frame(maxWidth: .infinity, minHeight: 46)
                .overlay(Rectangle().stroke(Color.industryLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var loadingRow: some View {
        Text("LOADING…")
            .industryKicker()
            .foregroundStyle(Color.industryFaint)
            .frame(maxWidth: .infinity)
            .padding(20)
    }

    private func emptyRow(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .industryKicker()
            .foregroundStyle(Color.industryFaint)
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
