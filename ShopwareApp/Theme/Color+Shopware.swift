//
//  Color+Shopware.swift
//  ShopwareApp
//
//  Shopware Administration-inspired semantic palette.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    static let appBackground = dynamic(
        light: Color(red: 0.94, green: 0.95, blue: 0.96),
        dark: Color(red: 0.06, green: 0.08, blue: 0.11)
    )
    static let surface = dynamic(
        light: .white,
        dark: Color(red: 0.11, green: 0.14, blue: 0.18)
    )
    static let controlBackground = dynamic(
        light: Color(red: 0.91, green: 0.94, blue: 0.96),
        dark: Color(red: 0.16, green: 0.20, blue: 0.26)
    )
    static let border = dynamic(
        light: Color(red: 0.82, green: 0.85, blue: 0.88),
        dark: Color(red: 0.24, green: 0.29, blue: 0.36)
    )
    static let primaryText = dynamic(
        light: Color(red: 0.08, green: 0.13, blue: 0.18),
        dark: Color(red: 0.93, green: 0.96, blue: 0.98)
    )
    static let secondaryText = dynamic(
        light: Color(red: 0.32, green: 0.40, blue: 0.48),
        dark: Color(red: 0.62, green: 0.70, blue: 0.78)
    )
    static let inverseText = Color.white
    static let shopwareBlue = dynamic(
        light: Color(red: 0.03, green: 0.44, blue: 1.0),
        dark: Color(red: 0.27, green: 0.58, blue: 1.0)
    )
    static let swNavy = Color(red: 0.10, green: 0.14, blue: 0.20)
    static let amber = dynamic(
        light: Color(red: 0.72, green: 0.45, blue: 0.05),
        dark: Color(red: 0.95, green: 0.67, blue: 0.24)
    )
    static let blue = dynamic(
        light: Color(red: 0.42, green: 0.27, blue: 0.76),
        dark: Color(red: 0.59, green: 0.48, blue: 0.96)
    )
    static let red = dynamic(
        light: Color(red: 0.87, green: 0.16, blue: 0.30),
        dark: Color(red: 1.0, green: 0.38, blue: 0.48)
    )
    static let errorText = dynamic(
        light: Color(red: 0.56, green: 0.11, blue: 0.09),
        dark: Color(red: 1.0, green: 0.62, blue: 0.58)
    )
    static let errorBackground = dynamic(
        light: Color(red: 1.0, green: 0.94, blue: 0.93),
        dark: Color(red: 0.22, green: 0.08, blue: 0.08)
    )
    static let errorBorder = dynamic(
        light: Color(red: 0.95, green: 0.71, blue: 0.68),
        dark: Color(red: 0.58, green: 0.20, blue: 0.20)
    )

    // Compatibility aliases keep the newer screen structure while restoring
    // the original Shopware/Meteor visual language.
    static let industryBackground = appBackground
    static let industrySurface = surface
    static let industrySunk = controlBackground
    static let industryText = primaryText
    static let industryDim = secondaryText
    static let industryFaint = secondaryText.opacity(0.78)
    static let industryAccent = shopwareBlue
    static let industryAccentDeep = shopwareBlue.opacity(0.82)
    static let industryAccentTint = shopwareBlue.opacity(0.10)
    static let industryInverse = inverseText
    static let industryLine = border
    static let industryHair = border.opacity(0.58)
    static let industryMark = border

    private static func dynamic(light: Color, dark: Color) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #elseif canImport(AppKit)
        return Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor(dark) : NSColor(light)
        })
        #else
        return light
        #endif
    }
}
