//
//  Animations.swift
//  ShopwareApp
//
//  Small animated accents: the live-connection pulse and the
//  staggered fade-and-rise entrance used by the dashboard cards.
//

import SwiftUI

// Soft radar pulse for the live connection indicator
struct PulsingDot: View {
    @State private var pulse = false
    private let green = Color(red: 0.22, green: 0.82, blue: 0.42)

    var body: some View {
        ZStack {
            Circle()
                .fill(green)
                .frame(width: 14, height: 14)
                .scaleEffect(pulse ? 1.8 : 0.6)
                .opacity(pulse ? 0 : 0.5)
            Circle()
                .fill(green)
                .frame(width: 7, height: 7)
        }
        .frame(width: 14, height: 14)
        .onAppear {
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

// Staggered fade-and-rise entrance for dashboard cards
struct RiseIn: ViewModifier {
    @State private var shown = false
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 16)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(delay)) {
                    shown = true
                }
            }
    }
}

extension View {
    func riseIn(_ delay: Double = 0) -> some View {
        modifier(RiseIn(delay: delay))
    }
}
