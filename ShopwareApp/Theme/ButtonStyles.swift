//
//  ButtonStyles.swift
//  ShopwareApp
//
//  Reusable button styles for the dashboard UI.
//

import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(Color.inverseText)
            .background(Color.shopwareBlue.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 48, height: 44)
            .foregroundStyle(Color.primaryText)
            .background(Color.controlBackground.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct IndustryActionButtonStyle: ButtonStyle {
    var outlined = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minHeight: 44)
            .foregroundStyle(outlined ? Color.shopwareBlue : Color.inverseText)
            .background(
                configuration.isPressed
                    ? Color.shopwareBlue.opacity(0.12)
                    : (outlined ? Color.clear : Color.shopwareBlue)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(outlined ? Color.shopwareBlue : Color.clear, lineWidth: 1)
            )
    }
}

// Springy press feedback for custom-styled buttons
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
