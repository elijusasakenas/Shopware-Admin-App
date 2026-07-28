//
//  Color+Shopware.swift
//  ShopwareApp
//
//  Semantic palette for the Industry dashboard design.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    static let industryBackground = dynamic(
        light: Color(red: 0.949, green: 0.949, blue: 0.953),
        dark: Color(red: 0.082, green: 0.106, blue: 0.129)
    )
    static let industrySurface = dynamic(
        light: .white,
        dark: Color(red: 0.110, green: 0.141, blue: 0.173)
    )
    static let industrySunk = dynamic(
        light: Color(red: 0.914, green: 0.914, blue: 0.918),
        dark: Color(red: 0.129, green: 0.169, blue: 0.204)
    )
    static let industryText = dynamic(
        light: Color(red: 0.114, green: 0.122, blue: 0.125),
        dark: Color(red: 0.933, green: 0.945, blue: 0.957)
    )
    static let industryDim = dynamic(
        light: Color(red: 0.365, green: 0.365, blue: 0.376),
        dark: Color(red: 0.655, green: 0.702, blue: 0.741)
    )
    static let industryFaint = dynamic(
        light: Color(red: 0.596, green: 0.596, blue: 0.608),
        dark: Color(red: 0.463, green: 0.510, blue: 0.549)
    )
    static let industryAccent = dynamic(
        light: Color(red: 0.349, green: 0.502, blue: 0.651),
        dark: Color(red: 0.580, green: 0.737, blue: 0.890)
    )
    static let industryAccentDeep = dynamic(
        light: Color(red: 0.173, green: 0.271, blue: 0.365),
        dark: Color(red: 0.710, green: 0.851, blue: 0.992)
    )
    static let industryAccentTint = dynamic(
        light: Color(red: 0.349, green: 0.502, blue: 0.651).opacity(0.10),
        dark: Color(red: 0.580, green: 0.737, blue: 0.890).opacity(0.12)
    )
    static let industryInverse = dynamic(
        light: Color(red: 0.961, green: 0.961, blue: 0.973),
        dark: Color(red: 0.082, green: 0.106, blue: 0.129)
    )
    static let industryLine = dynamic(
        light: Color(red: 0.114, green: 0.122, blue: 0.125).opacity(0.18),
        dark: Color(red: 0.949, green: 0.949, blue: 0.953).opacity(0.20)
    )
    static let industryHair = dynamic(
        light: Color(red: 0.114, green: 0.122, blue: 0.125).opacity(0.10),
        dark: Color(red: 0.949, green: 0.949, blue: 0.953).opacity(0.11)
    )
    static let industryMark = dynamic(
        light: Color(red: 0.114, green: 0.122, blue: 0.125).opacity(0.50),
        dark: Color(red: 0.949, green: 0.949, blue: 0.953).opacity(0.45)
    )

    // Existing call sites keep these semantic aliases while screens migrate.
    static let appBackground = industryBackground
    static let surface = industrySurface
    static let controlBackground = industrySunk
    static let border = industryLine
    static let primaryText = industryText
    static let secondaryText = industryDim
    static let inverseText = industryInverse
    static let shopwareBlue = industryAccent
    static let swNavy = industryText
    static let amber = industryAccent
    static let blue = industryAccent
    static let red = industryAccent
    static let errorText = industryText
    static let errorBackground = industrySurface
    static let errorBorder = industryLine

    static func dynamic(light: Color, dark: Color) -> Color {
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
