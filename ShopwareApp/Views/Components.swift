import SwiftUI

struct FormField: View {
    let title: LocalizedStringKey
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var isSecure = false
    var submitLabel: SubmitLabel = .next
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.secondaryText)
            Group {
                if isSecure { SecureField(placeholder, text: $text) }
                else { TextField(placeholder, text: $text) }
            }
            .autocorrectionDisabled()
            #if !os(macOS)
            .textInputAutocapitalization(.never)
            #endif
            .font(.body)
            .foregroundStyle(Color.primaryText)
            .tint(Color.shopwareBlue)
            .submitLabel(submitLabel)
            .onSubmit { onSubmit?() }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.border, lineWidth: 1)
            )
        }
    }
}

struct SectionHeader: View {
    let title: LocalizedStringKey
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.primaryText)
            Spacer()
            if let detail {
                Text(AppLocalization.string(String.LocalizationValue(detail)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.shopwareBlue)
            }
        }
    }
}

struct BlueprintFrame<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(max(padding, 16))
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.border.opacity(0.7), lineWidth: 1)
            )
    }
}

struct SeverityLadder: View {
    let level: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index < level ? Color.shopwareBlue : Color.border)
                    .frame(width: 16, height: 4)
            }
        }
        .frame(width: 16)
        .accessibilityLabel(level == 3 ? "Urgent" : level == 2 ? "Warning" : "Information")
    }
}

struct SquareToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Color.shopwareBlue : Color.controlBackground)
                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .padding(3)
                    .shadow(color: .black.opacity(0.16), radius: 1, y: 1)
            }
            .frame(width: 44, height: 24)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

struct StockStepper: View {
    let stock: Int
    var isBusy = false
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button { onChange(max(0, stock - 1)) } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(Color.controlBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .disabled(stock <= 0 || isBusy)
            .opacity(stock <= 0 ? 0.4 : 1)

            Text(stock.formatted())
                .font(.body.monospacedDigit().weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(stock < 0 ? Color.red : Color.primaryText)
                .frame(minWidth: 36, minHeight: 32)
                .background(stock < 0 ? Color.red.opacity(0.08) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            Button { onChange(stock + 1) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.inverseText)
                    .frame(width: 32, height: 32)
                    .background(Color.shopwareBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .disabled(isBusy)
        }
        .foregroundStyle(Color.shopwareBlue)
        .padding(4)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.border, lineWidth: 1)
        )
        .opacity(isBusy ? 0.45 : 1)
        .buttonStyle(.plain)
    }
}

struct AskBar: View {
    var draft: Binding<String>?
    var autoFocus = false
    var onSubmit: () -> Void
    @FocusState private var fieldFocused: Bool

    private var hasText: Bool {
        guard let draft else { return true }
        return !draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.shopwareBlue)
                if let draft {
                    TextField("Ask your shop assistant", text: draft)
                        .font(.body)
                        .focused($fieldFocused)
                        .submitLabel(.send)
                        .onSubmit(submit)
                    if fieldFocused {
                        Button {
                            fieldFocused = false
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Done")
                    }
                } else {
                    Text("Ask your shop assistant")
                        .font(.body)
                        .foregroundStyle(Color.secondaryText)
                    Spacer()
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(fieldFocused ? Color.shopwareBlue.opacity(0.55) : Color.border, lineWidth: 1)
            )
            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.inverseText)
                    .frame(width: 46, height: 46)
                    .background(hasText ? Color.shopwareBlue : Color.shopwareBlue.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Ask")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(Color.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.border.opacity(0.7)).frame(height: 1)
        }
        .task {
            guard autoFocus, draft != nil else { return }
            await Task.yield()
            fieldFocused = true
        }
    }

    private func submit() {
        fieldFocused = false
        onSubmit()
    }
}

struct OrderList: View {
    let orders: [LatestOrder]
    let isLoading: Bool
    var emptyMessage: LocalizedStringKey = "No orders today."

    var body: some View {
        VStack(spacing: 0) {
            if orders.isEmpty {
                Text(isLoading ? "Loading..." : emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(22)
            } else {
                ForEach(Array(orders.enumerated()), id: \.element.id) { index, order in
                    NavigationLink(value: order) {
                        HStack(spacing: 10) {
                            Text(order.orderNumber)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.primaryText)
                                .frame(width: 58, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(StateLocalization.stateName(order.state))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color.primaryText)
                                    .lineLimit(1)
                                Text(order.displayDate)
                                    .font(.caption)
                                    .foregroundStyle(Color.secondaryText)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(order.amountTotal.formatted(.currency(code: order.currencyCode)))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.primaryText)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.secondaryText)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle())
                    if index < orders.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
            }
        }
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.border.opacity(0.7), lineWidth: 1)
        )
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(Color.errorText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.errorBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.errorBorder, lineWidth: 1)
            )
    }
}

private struct ShopwareCardModifier: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.border.opacity(0.7), lineWidth: 1)
            )
    }
}

extension View {
    func shopwareCard(padding: CGFloat = 18) -> some View {
        modifier(ShopwareCardModifier(padding: padding))
    }
}
