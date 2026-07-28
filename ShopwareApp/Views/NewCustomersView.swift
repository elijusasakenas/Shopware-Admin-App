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
        .background(Color.industryBackground)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("NEW CUSTOMERS")
                    .industryKicker(11)
                    .foregroundStyle(Color.industryText)
            }
        }
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            do { customers = try await settings.recentCustomers() }
            catch { errorMessage = error.shopwareDisplayMessage }
            isLoading = false
        }
    }

    private var summaryPlate: some View {
        BlueprintFrame(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Registrations · Last 7 days")
                    .industryKicker()
                    .foregroundStyle(Color.industryFaint)
                HStack(spacing: 0) {
                    summaryCell(customers.count, label: "TOTAL")
                    Rectangle().fill(Color.industryHair).frame(width: 1, height: 42)
                    summaryCell(customers.filter { !$0.guest }.count, label: "ACCOUNTS")
                    Rectangle().fill(Color.industryHair).frame(width: 1, height: 42)
                    summaryCell(customers.filter(\.guest).count, label: "GUESTS")
                }
            }
        }
    }

    private func summaryCell(_ value: Int, label: LocalizedStringKey) -> some View {
        VStack(spacing: 3) {
            Text(value.formatted())
                .font(IndustryFont.display(30))
                .foregroundStyle(Color.industryText)
            Text(label).industryKicker(9).foregroundStyle(Color.industryFaint)
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
                        .industryKicker()
                        .foregroundStyle(filter == candidate ? Color.industryInverse : Color.industryDim)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .background(filter == candidate ? Color.industryAccent : Color.clear)
                        .overlay(Rectangle().stroke(Color.industryHair, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var customerRows: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.industryLine).frame(height: 1)
            if isLoading {
                emptyRow("LOADING…")
            } else if visibleCustomers.isEmpty {
                emptyRow("NO CUSTOMER REGISTRATIONS")
            } else {
                ForEach(visibleCustomers) { customer in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(customer.name.isEmpty ? customer.email : customer.name)
                                .font(IndustryFont.body(14.5, medium: true))
                                .foregroundStyle(Color.industryText)
                                .lineLimit(1)
                            Text(customerMeta(customer))
                                .industryKicker()
                                .foregroundStyle(Color.industryFaint)
                                .lineLimit(1)
                        }
                        Spacer()
                        SeverityLadder(level: customer.guest ? 1 : 2)
                        Text(customer.guest ? "GUEST" : "ACCOUNT")
                            .industryKicker()
                            .foregroundStyle(Color.industryDim)
                            .frame(width: 58, alignment: .trailing)
                    }
                    .padding(.vertical, 11)
                    Rectangle().fill(Color.industryHair).frame(height: 1)
                }
            }
        }
    }

    private func customerMeta(_ customer: CustomerRegistration) -> String {
        let format = Date.FormatStyle(date: .abbreviated, time: .shortened)
            .locale(AppLocalization.locale)
        let date = customer.createdAt?.formatted(format) ?? AppLocalization.string("NO DATE")
        return "\(customer.email) · \(date)"
    }

    private func emptyRow(_ label: LocalizedStringKey) -> some View {
        Text(label)
            .industryKicker()
            .foregroundStyle(Color.industryFaint)
            .frame(maxWidth: .infinity)
            .padding(24)
    }
}
