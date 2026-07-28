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
            .background(configuration.isPressed ? Color.industryAccentDeep : Color.industryAccent)
            .contentShape(Rectangle())
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 44, height: 44)
            .foregroundStyle(Color.industryDim)
            .background(configuration.isPressed ? Color.industryAccentTint : Color.clear)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct IndustryActionButtonStyle: ButtonStyle {
    var outlined = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minHeight: 44)
            .foregroundStyle(outlined ? Color.industryDim : Color.industryInverse)
            .background(
                configuration.isPressed
                    ? Color.industryAccentTint
                    : (outlined ? Color.clear : Color.industryAccent)
            )
            .overlay(Rectangle().stroke(outlined ? Color.industryLine : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
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
