import SwiftUI

struct NewCustomersView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "ALL"
        case accounts = "ACCOUNTS"
        case guests = "GUESTS"
        var id: String { rawValue }
    }

    @ObservedObject var settings: ShopSettingsViewModel
    @State private var customers: [CustomerRegistration] = []
    @State private var filter: Filter = .all
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var visibleCustomers: [CustomerRegistration] {
        customers.filter {
            switch filter {
            case .all: return true
            case .accounts: return !$0.guest
            case .guests: return $0.guest
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let errorMessage { ErrorBanner(message: errorMessage) }
                summaryPlate
                filterControl
                customerRows
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .background(Color.appBackground)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("NEW CUSTOMERS")
                    .font(.headline)
                    .foregroundStyle(Color.primaryText)
            }
        }
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            do { customers = try await settings.recentCustomers(since: DateRange.days7.sinceDate) }
            catch { errorMessage = error.shopwareDisplayMessage }
            isLoading = false
        }
    }

    private var summaryPlate: some View {
        BlueprintFrame(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Registrations · Last 7 days")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.secondaryText)
                HStack(spacing: 0) {
                    summaryCell(customers.count, label: "TOTAL")
                    Divider().frame(height: 42)
                    summaryCell(customers.filter { !$0.guest }.count, label: "ACCOUNTS")
                    Divider().frame(height: 42)
                    summaryCell(customers.filter(\.guest).count, label: "GUESTS")
                }
            }
        }
    }

    private func summaryCell(_ value: Int, label: LocalizedStringKey) -> some View {
        VStack(spacing: 3) {
            Text(value.formatted())
                .font(.title.weight(.semibold))
                .foregroundStyle(Color.primaryText)
            Text(label).font(.caption).foregroundStyle(Color.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private var filterControl: some View {
        HStack(spacing: 6) {
            ForEach(Filter.allCases) { candidate in
                Button {
                    filter = candidate
                } label: {
                        Text(AppLocalization.string(String.LocalizationValue(candidate.rawValue)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(filter == candidate ? Color.inverseText : Color.secondaryText)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .background(filter == candidate ? Color.shopwareBlue : Color.surface)
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

    private var customerRows: some View {
        VStack(spacing: 0) {
            if isLoading {
                emptyRow("LOADING…")
            } else if visibleCustomers.isEmpty {
                emptyRow("NO CUSTOMER REGISTRATIONS")
            } else {
                ForEach(visibleCustomers) { customer in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(customer.name.isEmpty ? customer.email : customer.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.primaryText)
                                .lineLimit(1)
                            Text(customerMeta(customer))
                                .font(.caption)
                                .foregroundStyle(Color.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer()
                        SeverityLadder(level: customer.guest ? 1 : 2)
                        Text(customer.guest ? "GUEST" : "ACCOUNT")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.secondaryText)
                            .frame(width: 58, alignment: .trailing)
                    }
                    .padding(.vertical, 11)
                    if customer.id != visibleCustomers.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.border, lineWidth: 1)
        )
    }

    private func customerMeta(_ customer: CustomerRegistration) -> String {
        let format = Date.FormatStyle(date: .abbreviated, time: .shortened)
            .locale(AppLocalization.locale)
        let date = customer.createdAt?.formatted(format) ?? AppLocalization.string("NO DATE")
        return "\(customer.email) · \(date)"
    }

    private func emptyRow(_ label: LocalizedStringKey) -> some View {
        Text(label)
            .font(.subheadline)
            .foregroundStyle(Color.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(24)
    }
}
