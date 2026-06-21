//
//  ShopHeaderView.swift
//  ShopwareApp
//
//  Dashboard header identity block. Tapping the shop name opens a switcher
//  to change between saved shops, add another, or remove the current one.
//

import SwiftUI

struct ShopHeaderView: View {
    @ObservedObject var viewModel: ShopwareDashboardViewModel
    @Binding var showSettings: Bool

    @State private var confirmRemoval = false

    private let accent = Color(red: 0.47, green: 0.71, blue: 1.0)
    private let subtitleColor = Color(red: 0.62, green: 0.69, blue: 0.78)

    private var hasMultipleShops: Bool { viewModel.savedConnections.count > 1 }

    var body: some View {
        HStack(spacing: 14) {
            Menu {
                shopSwitcherMenu
            } label: {
                switcherLabel
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Switch shop")

            Spacer()

            Button {
                showSettings = true
            } label: {
                headerIcon("gearshape.fill", size: 16)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Shop settings")

            Button {
                Task { await viewModel.disconnect() }
            } label: {
                headerIcon("rectangle.portrait.and.arrow.right", size: 15)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Sign out of all shops")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                colors: [Color(red: 0.14, green: 0.19, blue: 0.28), Color.swNavy],
                startPoint: .top, endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .confirmationDialog(
            "Remove this shop?",
            isPresented: $confirmRemoval,
            titleVisibility: .visible
        ) {
            if let current = viewModel.connection {
                Button("Remove \(current.displayName)", role: .destructive) {
                    Task { await viewModel.removeShop(current) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its saved credentials will be deleted from this device. Other shops stay connected.")
        }
    }

    // MARK: - Switcher menu content

    @ViewBuilder
    private var shopSwitcherMenu: some View {
        ForEach(viewModel.savedConnections) { shop in
            Button {
                Task { await viewModel.switchTo(shop) }
            } label: {
                if shop.id == viewModel.connection?.id {
                    Label(shop.displayName, systemImage: "checkmark")
                } else {
                    Text(shop.displayName)
                }
            }
        }

        Divider()

        Button {
            viewModel.beginAddingShop()
        } label: {
            Label("Add another shop…", systemImage: "plus")
        }

        if viewModel.connection != nil {
            Button(role: .destructive) {
                confirmRemoval = true
            } label: {
                Label("Remove this shop…", systemImage: "trash")
            }
        }
    }

    // MARK: - Label

    private var switcherLabel: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.18))
                Text(String((viewModel.connection?.displayName ?? "S").prefix(1)).uppercased())
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(accent)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(viewModel.connection?.displayName ?? "Shopware")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(subtitleColor)
                }
                HStack(spacing: 6) {
                    PulsingDot()
                    Text(viewModel.versionString.isEmpty
                         ? "Administration"
                         : "Administration \(viewModel.versionString)")
                        .font(.caption)
                        .foregroundStyle(subtitleColor)
                        .lineLimit(1)
                }
            }
        }
    }

    private func headerIcon(_ systemName: String, size: CGFloat) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size))
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: 38, height: 38)
            .background(Color.inverseText.opacity(0.08))
            .clipShape(Circle())
    }
}
