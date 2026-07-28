import SwiftUI

struct ShopHeaderView: View {
    @ObservedObject var viewModel: ShopwareDashboardViewModel
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    viewModel.isChannelPickerExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Text(String((viewModel.connection?.displayName ?? "S").prefix(1)).uppercased())
                        .font(.headline)
                        .foregroundStyle(Color.inverseText)
                        .frame(width: 34, height: 34)
                        .background(Color.shopwareBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.selectedChannelName)
                            .font(.headline)
                            .foregroundStyle(Color.primaryText)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            PulsingDot()
                            Text(statusLine)
                                .font(.caption)
                                .foregroundStyle(Color.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            Button {
                let current = AppAppearance(rawValue: appearance) ?? .system
                appearance = current == .dark ? AppAppearance.light.rawValue : AppAppearance.dark.rawValue
            } label: {
                Image(systemName: "sun.max")
                    .font(.system(size: 17, weight: .medium))
            }
            .buttonStyle(IconButtonStyle())
            .accessibilityLabel("Toggle appearance")

            if let client = viewModel.apiClient {
                NavigationLink {
                    ShopSettingsView(
                        session: viewModel,
                        settings: ShopSettingsViewModel(client: client)
                    )
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 17, weight: .medium))
                }
                .buttonStyle(IconButtonStyle())
                .accessibilityLabel("Shop settings")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.border.opacity(0.7)).frame(height: 1)
        }
    }

    private var statusLine: String {
        let version = viewModel.versionString.isEmpty ? "Administration" : viewModel.versionString
        return "\(viewModel.connection?.displayName ?? "Shopware") · \(version)"
    }
}
