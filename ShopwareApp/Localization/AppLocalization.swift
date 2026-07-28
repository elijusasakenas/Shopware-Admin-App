import Foundation

/// Resolves runtime localization values with the language selected inside the app.
///
/// SwiftUI views receive the selected locale through the environment, but
/// `String(localized:)` otherwise falls back to the device locale.
enum AppLocalization {
    nonisolated static var language: String {
        UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
    }

    nonisolated static var locale: Locale {
        return language == "system" ? .autoupdatingCurrent : Locale(identifier: language)
    }

    nonisolated static func string(
        _ value: String.LocalizationValue,
        table: String? = nil
    ) -> String {
        guard language != "system",
              let localizationURL = Bundle.main.url(
                forResource: language,
                withExtension: "lproj"
              ),
              let localizationBundle = Bundle(url: localizationURL)
        else {
            return String(localized: value, table: table, locale: locale)
        }

        return String(
            localized: value,
            table: table,
            bundle: localizationBundle,
            locale: locale
        )
    }
}
