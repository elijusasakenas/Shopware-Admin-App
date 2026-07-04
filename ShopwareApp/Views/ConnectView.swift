//
//  ConnectView.swift
//  ShopwareApp
//
//  Credential-entry screen. Shown full-screen when no shop is saved, and as
//  a sheet ("Add another shop") when connecting an additional shop.
//

import SwiftUI

struct ConnectView: View {
    @ObservedObject var viewModel: ShopwareDashboardViewModel
    @State private var shopName = ""
    @State private var shopURL = ""
    @State private var accessKey = ""
    @State private var secretKey = ""

    /// True when presented as a sheet over an existing shop.
    private var isAddingAdditionalShop: Bool { viewModel.isAddingShop }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Shopware Admin API")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.shopwareBlue)
                            .textCase(.uppercase)
                        Text(isAddingAdditionalShop ? "Add another shop" : "Connect your shop")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(Color.primaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        Link(destination: URL(string: "https://docs.shopware.com/en/shopware-6-en/settings/system/integrationen")!) {
                            HStack(spacing: 6) {
                                Image(systemName: "questionmark.circle")
                                Text("How to get your access keys")
                                    .fixedSize(horizontal: false, vertical: true)
                                Image(systemName: "arrow.up.right")
                                    .font(.caption2.weight(.bold))
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.shopwareBlue)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.top, isAddingAdditionalShop ? 12 : 36)

                    VStack(spacing: 16) {
                        FormField(title: "Shop name (optional)", placeholder: "My store", text: $shopName)
                        FormField(title: "Shop URL", placeholder: "https://your-shop.com", text: $shopURL)
                        FormField(title: "Access key ID", placeholder: "SWIA...", text: $accessKey)
                        FormField(title: "Secret access key", placeholder: "Secret", text: $secretKey, isSecure: true)
                    }

                    if let msg = viewModel.errorMessage { ErrorBanner(message: msg) }

                    Button {
                        Task {
                            let trimmedName = shopName.trimmingCharacters(in: .whitespacesAndNewlines)
                            await viewModel.connect(
                                ShopwareConnection(
                                    shopURL: shopURL,
                                    accessKey: accessKey,
                                    secretKey: secretKey,
                                    label: trimmedName.isEmpty ? nil : trimmedName
                                )
                            )
                        }
                    } label: {
                        if viewModel.isLoading { ProgressView().tint(.white) }
                        else { Text(isAddingAdditionalShop ? "Add shop" : "Connect").fontWeight(.bold) }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canConnect || viewModel.isLoading)
                }
                .padding(22)
            }
            .background(Color.appBackground)
            .toolbar {
                if isAddingAdditionalShop {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { viewModel.cancelAddingShop() }
                    }
                }
            }
        }
    }

    private var canConnect: Bool {
        !shopURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !accessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !secretKey.isEmpty
    }
}
