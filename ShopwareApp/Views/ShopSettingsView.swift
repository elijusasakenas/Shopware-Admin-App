//
//  ShopSettingsView.swift
//  ShopwareApp
//
//  Shop settings sheet: app language/appearance, subpages, maintenance
//  toggles, promotion activation, and newsletter signups.
//

import SwiftUI

struct ShopSettingsView: View {
    @ObservedObject var session: ShopwareDashboardViewModel
    @ObservedObject var settings: ShopSettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var appLanguageCode = AppLanguage.system.rawValue
    @AppStorage(AppAppearance.storageKey) private var appAppearanceCode = AppAppearance.system.rawValue

    @State private var promotions: [Promotion] = []
    @State private var recipients: [NewsletterRecipient] = []
    @State private var visiblePromotionCount = 5
    @State private var visibleRecipientCount = 5
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let listBatchSize = 10

    private var visiblePromotions: [Promotion] {
        Array(promotions.prefix(visiblePromotionCount))
    }

    private var visibleRecipients: [NewsletterRecipient] {
        Array(recipients.prefix(visibleRecipientCount))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let errorMessage { ErrorBanner(message: errorMessage) }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("App language")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.primaryText)
                        Picker("App language", selection: $appLanguageCode) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.title).tag(language.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.shopwareBlue)

                        Divider()

                        Text("Appearance")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.primaryText)
                        Picker("Appearance", selection: $appAppearanceCode) {
                            ForEach(AppAppearance.allCases) { appearance in
                                Text(appearance.title).tag(appearance.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.border, lineWidth: 1))

                    AIAssistantSettingsCard()

                    if isLoading {
                        ProgressView()
                            .tint(.shopwareBlue)
                            .frame(maxWidth: .infinity)
                            .padding(40)
                    } else {
                        // Subpages
                        VStack(spacing: 0) {
                            NavigationLink {
                                NewCustomersView(settings: settings)
                            } label: {
                                SettingsRow(icon: "person.crop.circle.badge.plus", title: "New customer registrations")
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 52)
                            NavigationLink {
                                ShopStatusView(settings: settings)
                            } label: {
                                SettingsRow(icon: "waveform.path.ecg", title: "Shop status & log")
                            }
                            .buttonStyle(.plain)
                        }
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.border, lineWidth: 1))

                        // Maintenance mode
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Maintenance mode")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.primaryText)
                            Text("Visitors see a maintenance page while enabled.")
                                .font(.caption)
                                .foregroundStyle(Color.secondaryText)

                            ForEach(session.salesChannels) { channel in
                                Toggle(isOn: maintenanceBinding(for: channel)) {
                                    Text(channel.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.primaryText)
                                }
                                .tint(.shopwareBlue)
                                .padding(.vertical, 4)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.border, lineWidth: 1))

                        // Marketing / promotions
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Marketing")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.primaryText)
                            Text("Enable or disable promotions instantly.")
                                .font(.caption)
                                .foregroundStyle(Color.secondaryText)

                            if promotions.isEmpty {
                                Text("No promotions yet. Create them in the admin under Marketing > Promotions.")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.secondaryText)
                                    .padding(.vertical, 8)
                            } else {
                                ForEach(visiblePromotions) { promotion in
                                    Toggle(isOn: promotionBinding(for: promotion)) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(promotion.name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(Color.primaryText)
                                            if let code = promotion.code, !code.isEmpty {
                                                Text("Code: \(code)")
                                                    .font(.caption)
                                                    .foregroundStyle(Color.secondaryText)
                                            }
                                        }
                                    }
                                    .tint(.shopwareBlue)
                                    .padding(.vertical, 4)
                                }

                                if visiblePromotionCount < promotions.count {
                                    showMoreButton("Show more promotions") {
                                        visiblePromotionCount = min(visiblePromotionCount + listBatchSize, promotions.count)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.border, lineWidth: 1))

                        // Newsletter registrations
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Newsletter signups")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.primaryText)
                            Text("Latest registrations, newest first.")
                                .font(.caption)
                                .foregroundStyle(Color.secondaryText)

                            if recipients.isEmpty {
                                Text("No newsletter registrations yet.")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.secondaryText)
                                    .padding(.vertical, 8)
                            } else {
                                ForEach(visibleRecipients) { recipient in
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(recipient.email)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(Color.primaryText)
                                                .lineLimit(1)
                                            if let createdAt = recipient.createdAt {
                                                Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                                                    .font(.caption)
                                                    .foregroundStyle(Color.secondaryText)
                                            }
                                        }
                                        Spacer()
                                        Text(recipient.statusLabel)
                                            .font(.caption.weight(.bold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(statusColor(recipient.status).opacity(0.12))
                                            .foregroundStyle(statusColor(recipient.status))
                                            .clipShape(Capsule())
                                    }
                                    .padding(.vertical, 5)
                                    if recipient.id != visibleRecipients.last?.id { Divider() }
                                }

                                if visibleRecipientCount < recipients.count {
                                    showMoreButton("Show more newsletter signups") {
                                        visibleRecipientCount = min(visibleRecipientCount + listBatchSize, recipients.count)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.border, lineWidth: 1))
                    }
                }
                .padding(20)
            }
            .background(Color.appBackground)
            .navigationTitle("Shop settings")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        do {
            async let promos = settings.promotions()
            async let news = settings.newsletterRecipients()
            promotions = try await promos
            recipients = try await news
            visiblePromotionCount = min(visiblePromotionCount, max(promotions.count, 5))
            visibleRecipientCount = min(visibleRecipientCount, max(recipients.count, 5))
        } catch {
            errorMessage = error.shopwareDisplayMessage
        }
        isLoading = false
    }

    private func showMoreButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                action()
            }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.shopwareBlue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.shopwareBlue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "optIn":  return .shopwareBlue
        case "direct": return .blue
        case "optOut": return .red
        default:       return .amber
        }
    }

    private func promotionBinding(for promotion: Promotion) -> Binding<Bool> {
        Binding(
            get: { promotions.first { $0.id == promotion.id }?.active ?? false },
            set: { newValue in
                Task {
                    do {
                        try await settings.setPromotionActive(promotionID: promotion.id, active: newValue)
                        if let index = promotions.firstIndex(where: { $0.id == promotion.id }) {
                            promotions[index].active = newValue
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
            get: { session.salesChannels.first { $0.id == channel.id }?.maintenance ?? false },
            set: { newValue in
                Task {
                    do { try await session.setMaintenance(channelID: channel.id, enabled: newValue) }
                    catch { errorMessage = error.shopwareDisplayMessage }
                }
            }
        )
    }
}

struct SettingsRow: View {
    let icon: String
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(Color.shopwareBlue)
                .frame(width: 28)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primaryText)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.secondaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
