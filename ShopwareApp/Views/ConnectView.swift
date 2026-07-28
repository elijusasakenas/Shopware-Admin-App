import SwiftUI

struct ConnectView: View {
    @ObservedObject var viewModel: ShopwareDashboardViewModel
    @State private var shopName = ""
    @State private var shopURL = ""
    @State private var accessKey = ""
    @State private var secretKey = ""

    private var isAddingAdditionalShop: Bool { viewModel.isAddingShop }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Shopware Admin API")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.shopwareBlue)
                        Text("Connect your shop")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Color.primaryText)
                        Text("Create an integration in Shopware Administration and enter its access keys here. Credentials remain in the device keychain.")
                            .font(.subheadline)
                            .foregroundStyle(Color.secondaryText)
                            .lineSpacing(5)
                        Link(
                            destination: URL(
                                string: "https://docs.shopware.com/en/shopware-6-en/settings/system/integrationen"
                            )!
                        ) {
                            HStack(spacing: 6) {
                                Text("HOW TO GET YOUR ACCESS KEYS")
                                    .font(.caption.weight(.semibold))
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .light))
                            }
                            .foregroundStyle(Color.shopwareBlue)
                        }
                        .padding(.top, 3)
                    }
                    .padding(.top, isAddingAdditionalShop ? 8 : 34)

                    VStack(spacing: 14) {
                        FormField(title: "Shop name (optional)", placeholder: "My store", text: $shopName)
                        FormField(title: "Shop URL", placeholder: "https://your-shop.com", text: $shopURL)
                        FormField(title: "Access key ID", placeholder: "SWIA...", text: $accessKey)
                        FormField(title: "Secret access key", placeholder: "Secret", text: $secretKey, isSecure: true)
                    }

                    if let message = viewModel.errorMessage {
                        ErrorBanner(message: message)
                    }

                    Button {
                        connect()
                    } label: {
                        Text(viewModel.isLoading ? "CONNECTING…" : "CONNECT")
                            .font(.headline)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canConnect || viewModel.isLoading)
                    .opacity(canConnect ? 1 : 0.45)

                    BlueprintFrame(padding: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Before you ship this publicly")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.shopwareBlue)
                            Text("Route AI requests through the included proxy, keep service secrets out of the app bundle, and use the narrowest Shopware integration permissions your workflow needs.")
                                .font(.caption)
                                .foregroundStyle(Color.secondaryText)
                                .lineSpacing(4)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 34)
            }
            .background(Color.appBackground)
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("ADD A SHOP")
                        .font(.headline)
                        .foregroundStyle(Color.primaryText)
                }
                if isAddingAdditionalShop {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("CANCEL") { viewModel.cancelAddingShop() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.shopwareBlue)
                    }
                }
            }
        }
    }

    private func connect() {
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
    }

    private var canConnect: Bool {
        !shopURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !accessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !secretKey.isEmpty
    }
}
