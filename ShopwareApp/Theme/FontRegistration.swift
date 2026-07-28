import CoreText
import Foundation

enum AppFontRegistration {
    private static let fontNames = [
        "Barlow-Regular",
        "Barlow-Medium",
        "BarlowCondensed-SemiBold"
    ]

    static func registerBundledFonts() {
        for name in fontNames {
            let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.main.url(forResource: name, withExtension: "ttf")
            guard let url else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
