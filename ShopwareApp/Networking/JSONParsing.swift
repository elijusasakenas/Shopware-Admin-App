//
//  JSONParsing.swift
//  ShopwareApp
//
//  Free helpers for decoding Shopware Admin API responses. Rows arrive
//  as JSON:API ({"attributes": {...}}) or plain JSON depending on Accept
//  handling, so these normalize both shapes and parse common value types.
//

import Foundation

func errorMessage(from payload: Any, status: Int) -> String {
    guard let json = payload as? [String: Any],
          let errors = json["errors"] as? [[String: Any]],
          let first = errors.first else {
        return "Shopware request failed with status \(status)."
    }
    let message = first["detail"] as? String ?? first["title"] as? String ?? "Shopware request failed with status \(status)."
    if message.localizedCaseInsensitiveContains("Client authentication failed") {
        return "Client authentication failed. Use the exact Access key ID and Secret access key from the same saved Shopware integration. If you created a new integration or regenerated the secret, copy the new pair again."
    }
    return message
}

// Admin API rows are JSON:API ({"attributes": {...}}) or plain JSON depending on Accept handling
func entityAttributes(of row: [String: Any]) -> [String: Any] {
    row["attributes"] as? [String: Any] ?? row
}

func relationshipID(from relationship: Any?) -> String? {
    guard let rel = relationship as? [String: Any], let data = rel["data"] as? [String: Any] else { return nil }
    return data["id"] as? String
}

/// Returns the state's language-neutral `technicalName` (e.g. "open",
/// "in_progress", "paid", "shipped"). The app localizes this key itself, so
/// it stays in the app's language regardless of the shop's API-context
/// language. Falls back to the shop-translated name only if no technical name
/// is present.
func orderStateTechnicalName(from attributes: [String: Any], includedState: [String: Any]?) -> String {
    if let embedded = attributes["stateMachineState"] as? [String: Any] {
        return embedded["technicalName"] as? String ?? translatedName(from: embedded) ?? "Unknown"
    }
    return includedState?["technicalName"] as? String ?? includedState.flatMap(translatedName) ?? "Unknown"
}

func translatedName(from attributes: [String: Any]) -> String? {
    (attributes["translated"] as? [String: Any])?["name"] as? String
}

func decimal(from value: Any?) -> Decimal {
    if let d = value as? Decimal { return d }
    if let n = value as? NSNumber { return n.decimalValue }
    if let s = value as? String { return Decimal(string: s) ?? 0 }
    return 0
}

func date(from value: String?) -> Date? {
    guard let value else { return nil }
    return ISO8601DateFormatter.shopware.date(from: value)
}

// Histogram bucket keys come in plain formats like "2026-06-01" or "2026-06-01 10:00"
func parseHistogramDate(_ key: String) -> Date? {
    for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd", "yyyy-MM"] {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        if let date = formatter.date(from: key) { return date }
    }
    return ISO8601DateFormatter.shopware.date(from: key) ?? ISO8601DateFormatter.shopwareDate.date(from: key)
}
