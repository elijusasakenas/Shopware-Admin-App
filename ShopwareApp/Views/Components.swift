//
//  Components.swift
//  ShopwareApp
//
//  Small reusable views shared across screens: form fields, KPI cards,
//  the orders list, and the error banner.
//

import SwiftUI

struct FormField: View {
    let title: LocalizedStringKey
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var isSecure = false

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
            .font(.body)
            .foregroundStyle(Color.primaryText)
            .tint(Color.shopwareBlue)
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.border, lineWidth: 1))
        }
    }
}

struct MetricCard: View {
    let title: LocalizedStringKey
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle().fill(accent).frame(width: 8, height: 8)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: value)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(16)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.border.opacity(0.7), lineWidth: 1))
    }
}

struct OrderList: View {
    let orders: [LatestOrder]
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 0) {
            if orders.isEmpty {
                Group {
                    if isLoading {
                        Text("Loading...")
                    } else {
                        Text("No orders today.")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Color.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(18)
            } else {
                ForEach(orders) { order in
                    NavigationLink(value: order) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(order.orderNumber)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Color.primaryText)
                                    .lineLimit(1)
                                Text("\(order.displayDate) · \(StateLocalization.stateName(order.state))")
                                    .font(.caption)
                                    .foregroundStyle(Color.secondaryText)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(order.amountTotal.formatted(.currency(code: order.currencyCode)))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.primaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.secondaryText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if order.id != orders.last?.id {
                        Divider().padding(.leading, 14)
                    }
                }
            }
        }
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.border, lineWidth: 1))
    }
}

struct ErrorBanner: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(Color.errorText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.errorBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.errorBorder, lineWidth: 1))
    }
}
