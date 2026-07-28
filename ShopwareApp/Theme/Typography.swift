import SwiftUI

enum IndustryFont {
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    static func body(_ size: CGFloat, medium: Bool = false) -> Font {
        .system(size: size, weight: medium ? .medium : .regular)
    }

    static func kicker(_ size: CGFloat = 9.5) -> Font {
        .system(size: max(11, size), weight: .semibold)
    }
}

extension View {
    func industryKicker(_ size: CGFloat = 9.5) -> some View {
        font(IndustryFont.kicker(size))
    }
}
