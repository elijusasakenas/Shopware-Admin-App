//
//  View+OnValueChange.swift
//  ShopwareApp
//
//  `onChange(of:perform:)` is deprecated from iOS 17 / macOS 14, but its
//  replacement does not exist on iOS 16, which the app still supports.
//  This wrapper picks the right one per platform and OS version.
//

import SwiftUI

extension View {
    /// Runs `action` with the new value whenever `value` changes.
    func onValueChange<Value: Equatable>(
        of value: Value,
        perform action: @escaping (Value) -> Void
    ) -> some View {
        modifier(OnValueChangeModifier(value: value, action: action))
    }
}

private struct OnValueChangeModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let action: (Value) -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
        // The macOS deployment target is 14.0, so the new API is always available.
        content.onChange(of: value) { _, newValue in action(newValue) }
        #else
        if #available(iOS 17.0, *) {
            content.onChange(of: value) { _, newValue in action(newValue) }
        } else {
            content.onChange(of: value) { newValue in action(newValue) }
        }
        #endif
    }
}
