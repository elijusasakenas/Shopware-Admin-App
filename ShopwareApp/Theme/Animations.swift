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

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.industryAccent)
                .frame(width: 6, height: 6)
                .scaleEffect(pulse ? 2 : 1)
                .opacity(pulse ? 0 : 0.5)
            Rectangle()
                .fill(Color.industryAccent)
                .frame(width: 6, height: 6)
        }
        .frame(width: 12, height: 12)
        .onAppear {
            withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) {
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
