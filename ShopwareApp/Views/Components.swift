import SwiftUI

struct FormField: View {
    let title: LocalizedStringKey
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var isSecure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .industryKicker()
                .foregroundStyle(Color.industryFaint)
            Group {
                if isSecure { SecureField(placeholder, text: $text) }
                else { TextField(placeholder, text: $text) }
            }
            .autocorrectionDisabled()
            .font(IndustryFont.body(15))
            .foregroundStyle(Color.industryText)
            .tint(Color.industryAccent)
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(Color.industrySurface)
            .overlay(Rectangle().stroke(Color.industryLine, lineWidth: 1))
        }
    }
}

struct SectionHeader: View {
    let title: LocalizedStringKey
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(IndustryFont.display(20))
                .foregroundStyle(Color.industryText)
            Spacer()
            if let detail {
                Text(AppLocalization.string(String.LocalizationValue(detail)))
                    .industryKicker()
                    .foregroundStyle(Color.industryFaint)
            }
        }
    }
}

struct BlueprintFrame<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(Color.industrySurface)
            .overlay(Rectangle().stroke(Color.industryLine, lineWidth: 1))
            .overlay(RegistrationMarks().allowsHitTesting(false))
    }
}

private struct RegistrationMarks: View {
    var body: some View {
        GeometryReader { geometry in
            let points = [
                CGPoint(x: 0, y: 0),
                CGPoint(x: geometry.size.width, y: 0),
                CGPoint(x: 0, y: geometry.size.height),
                CGPoint(x: geometry.size.width, y: geometry.size.height)
            ]
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                Path { path in
                    path.move(to: CGPoint(x: point.x - 5, y: point.y))
                    path.addLine(to: CGPoint(x: point.x + 5, y: point.y))
                    path.move(to: CGPoint(x: point.x, y: point.y - 5))
                    path.addLine(to: CGPoint(x: point.x, y: point.y + 5))
                }
                .stroke(Color.industryMark, lineWidth: 1)
            }
        }
        .padding(-6)
    }
}

struct SeverityLadder: View {
    let level: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Rectangle()
                    .fill(index < level ? Color.industryAccent : Color.clear)
                    .frame(width: 16, height: 3)
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
                Rectangle()
                    .fill(isOn ? Color.industryAccentTint : Color.clear)
                    .overlay(Rectangle().stroke(Color.industryLine, lineWidth: 1))
                Rectangle()
                    .fill(Color.industryAccent)
                    .frame(width: 18, height: 18)
                    .padding(2)
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
        HStack(spacing: 0) {
            Button { onChange(max(0, stock - 1)) } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .light))
                    .frame(width: 38, height: 38)
            }
            .disabled(stock == 0 || isBusy)
            Text(stock.formatted())
                .font(IndustryFont.display(17))
                .monospacedDigit()
                .foregroundStyle(Color.industryText)
                .frame(minWidth: 34)
            Button { onChange(stock + 1) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .light))
                    .frame(width: 38, height: 38)
                    .background(Color.industryAccentTint)
            }
            .disabled(isBusy)
        }
        .foregroundStyle(Color.industryAccent)
        .overlay(Rectangle().stroke(Color.industryLine, lineWidth: 1))
        .opacity(isBusy ? 0.45 : 1)
        .buttonStyle(.plain)
    }
}

struct AskBar: View {
    var draft: Binding<String>?
    var autoFocus = false
    var onSubmit: () -> Void
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(Color.industryAccent)
                if let draft {
                    TextField("Ask your shop assistant", text: draft)
                        .font(IndustryFont.body(15))
                        .focused($fieldFocused)
                        .onSubmit(onSubmit)
                } else {
                    Text("Ask your shop assistant")
                        .font(IndustryFont.body(15))
                        .foregroundStyle(Color.industryDim)
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.industrySurface)
            .overlay(Rectangle().stroke(Color.industryLine, lineWidth: 1))
            Button(action: onSubmit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(Color.industryInverse)
                    .frame(width: 44, height: 44)
                    .background(Color.industryAccent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color.industryBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.industryLine).frame(height: 1)
        }
        .task {
            guard autoFocus, draft != nil else { return }
            await Task.yield()
            fieldFocused = true
        }
    }
}

struct OrderList: View {
    let orders: [LatestOrder]
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.industryLine).frame(height: 1)
            if orders.isEmpty {
                Text(isLoading ? "LOADING…" : "NO ORDERS TODAY")
                    .industryKicker()
                    .foregroundStyle(Color.industryFaint)
                    .frame(maxWidth: .infinity)
                    .padding(22)
            } else {
                ForEach(orders) { order in
                    NavigationLink(value: order) {
                        HStack(spacing: 10) {
                            Text(order.orderNumber)
                                .font(IndustryFont.display(16))
                                .foregroundStyle(Color.industryText)
                                .frame(width: 58, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(StateLocalization.stateName(order.state))
                                    .font(IndustryFont.body(14, medium: true))
                                    .foregroundStyle(Color.industryText)
                                    .lineLimit(1)
                                Text(order.displayDate)
                                    .industryKicker(9)
                                    .foregroundStyle(Color.industryFaint)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(order.amountTotal.formatted(.currency(code: order.currencyCode)))
                                .font(IndustryFont.display(17))
                                .foregroundStyle(Color.industryText)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .light))
                                .foregroundStyle(Color.industryFaint)
                        }
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Rectangle().fill(Color.industryHair).frame(height: 1)
                }
            }
        }
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            SeverityLadder(level: 3)
            Text(message)
                .font(IndustryFont.body(14))
                .foregroundStyle(Color.industryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.industrySurface)
        .overlay(Rectangle().stroke(Color.industryLine, lineWidth: 1))
    }
}
