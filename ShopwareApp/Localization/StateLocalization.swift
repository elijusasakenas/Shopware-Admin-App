//
//  StateLocalization.swift
//  ShopwareApp
//
//  Translates Shopware state machine `technicalName`s (order / payment /
//  delivery states) and transition action names into the app's language.
//
//  Shopware returns state names already translated into the *shop's* API
//  context language, which does not follow the app's language setting. To make
//  states track the app language we carry the language-neutral `technicalName`
//  through the networking layer and localize it here.
//
//  Runtime strings are resolved with `AppLocalization` so they use the
//  language selected inside the app. Unknown/custom states fall back to a
//  humanized form of the key (e.g. "paid_partially" -> "Paid partially").
//

import Foundation

enum StateLocalization {

    /// Localized label for a state's `technicalName` (e.g. "open", "paid").
    static func stateName(_ technicalName: String) -> String {
        localized(prefix: "state", key: technicalName)
    }

    /// Localized label for a transition's destination state. The value carried
    /// is the target state's `technicalName`, so it uses the same table.
    static func transitionName(_ targetStateTechnicalName: String) -> String {
        localized(prefix: "state", key: targetStateTechnicalName)
    }

    // MARK: - Lookup

    /// Look up "<prefix>.<key>" in the state strings table. If the catalog has
    /// no entry (custom state), fall back to a humanized version of the key.
    private static func localized(prefix: String, key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return humanized("Unknown") }

        let lookupKey = "\(prefix).\(trimmed)"
        let resolved = AppLocalization.string(String.LocalizationValue(lookupKey), table: nil)

        // The localization API returns the key itself when there's no match.
        return resolved == lookupKey ? humanized(trimmed) : resolved
    }

    /// "paid_partially" / "in-progress" -> "Paid partially" / "In progress".
    private static func humanized(_ technicalName: String) -> String {
        let words = technicalName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map(String.init)
        guard let first = words.first else { return technicalName }

        let rest = words.dropFirst().map { $0.lowercased() }
        return ([first.capitalized] + rest).joined(separator: " ")
    }
}
