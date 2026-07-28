import SwiftUI

enum IndustryFont {
    static func display(_ size: CGFloat) -> Font {
        .custom("BarlowCondensed-SemiBold", size: size)
    }

    static func body(_ size: CGFloat, medium: Bool = false) -> Font {
        .custom(medium ? "Barlow-Medium" : "Barlow-Regular", size: size)
    }

    static func kicker(_ size: CGFloat = 9.5) -> Font {
        display(size)
    }
}

extension View {
    func industryKicker(_ size: CGFloat = 9.5) -> some View {
        font(IndustryFont.kicker(size))
            .tracking(size * 0.10)
            .textCase(.uppercase)
    }
}
