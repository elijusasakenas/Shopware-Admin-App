//
//  NewCustomersView.swift
//  ShopwareApp
//
//  Recent customer registrations, distinguishing accounts from guests.
//

import SwiftUI

struct NewCustomersView: View {
    @ObservedObject var settings: ShopSettingsViewModel

    @State private var customers: [CustomerRegistration] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let errorMessage { ErrorBanner(message: errorMessage) }

                if isLoading {
                    ProgressView().tint(.shopwareBlue).frame(maxWidth: .infinity).padding(40)
                } else if customers.isEmpty {
                    Text("No customer registrations yet.")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(40)
                } else {
                    VStack(spacing: 0) {
                        ForEach(customers) { customer in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(customer.name.isEmpty ? customer.email : customer.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.primaryText)
                                        .lineLimit(1)
                                    Text(customer.email)
                                        .font(.caption)
                                        .foregroundStyle(Color.secondaryText)
                                        .lineLimit(1)
                                    if let createdAt = customer.createdAt {
                                        Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(Color.secondaryText)
                                    }
                                }
                                Spacer()
                                Group {
                                    if customer.guest {
                                        Text("Guest")
                                    } else {
                                        Text("Account")
                                    }
                                }
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background((customer.guest ? Color.amber : Color.shopwareBlue).opacity(0.12))
                                    .foregroundStyle(customer.guest ? Color.amber : Color.shopwareBlue)
                                    .clipShape(Capsule())
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            if customer.id != customers.last?.id {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.border, lineWidth: 1))
                }
            }
            .padding(20)
        }
        .background(Color.appBackground)
        .navigationTitle("New customers")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            do { customers = try await settings.recentCustomers() }
            catch { errorMessage = error.shopwareDisplayMessage }
            isLoading = false
        }
    }
}
