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
                        .font(IndustryFont.display(19))
                        .foregroundStyle(Color.industryInverse)
                        .frame(width: 34, height: 34)
                        .background(Color.industryAccent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.selectedChannelName)
                            .font(IndustryFont.display(17))
                            .tracking(0.17)
                            .foregroundStyle(Color.industryText)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            PulsingDot()
                            Text(statusLine)
                                .industryKicker()
                                .foregroundStyle(Color.industryFaint)
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
                    .font(.system(size: 17, weight: .light))
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
                        .font(.system(size: 17, weight: .light))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(Color.industryDim)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("Shop settings")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color.industryBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.industryHair).frame(height: 1)
        }
    }

    private var statusLine: String {
        let version = viewModel.versionString.isEmpty ? "ADMINISTRATION" : viewModel.versionString
        return "\(viewModel.connection?.displayName.uppercased() ?? "SHOPWARE") · \(version)"
    }
}
