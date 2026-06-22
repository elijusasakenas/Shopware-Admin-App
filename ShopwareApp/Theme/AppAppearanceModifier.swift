//
//  AppAppearanceModifier.swift
//  ShopwareApp
//
//  Applies the user's chosen light/dark/system appearance. Sheets present in
//  their own context and do not inherit `preferredColorScheme` live, so this
//  modifier is applied to the root *and* to each sheet's content — that way an
//  appearance change in settings takes effect immediately, even while the
//  settings sheet is still open.
//

import SwiftUI

private struct AppAppearanceModifier: ViewModifier {
    @AppStorage(AppAppearance.storageKey) private var appAppearanceCode = AppAppearance.system.rawValue

    func body(content: Content) -> some View {
        content.preferredColorScheme(AppAppearance(rawValue: appAppearanceCode)?.colorScheme)
    }
}

extension View {
    /// Applies the app's selected appearance (light / dark / system). Apply this
    /// to top-level scenes and to every sheet's root content so the choice
    /// updates live across all presentation contexts.
    func appAppearance() -> some View {
        modifier(AppAppearanceModifier())
    }
}
