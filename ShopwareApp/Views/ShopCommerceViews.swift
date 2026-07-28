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
