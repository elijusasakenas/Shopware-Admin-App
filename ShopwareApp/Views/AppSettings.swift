//
//  AppSettings.swift
//  ShopwareApp
//
//  User-selectable app language and appearance, persisted via @AppStorage.
//

import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    static let storageKey = "appLanguage"

    case system
    case english = "en"
    case spanish = "es"
    case german = "de"

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system: return .autoupdatingCurrent
        case .english: return Locale(identifier: "en")
        case .spanish: return Locale(identifier: "es")
        case .german: return Locale(identifier: "de")
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .system: return "System language"
        case .english: return "English"
        case .spanish: return "Spanish"
        case .german: return "German"
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    static let storageKey = "appAppearance"

    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}
