import XCTest
@testable import ShopwareApp

final class AppLocalizationTests: XCTestCase {
    func testRuntimeStringsFollowTheLanguageSelectedInsideTheApp() {
        let defaults = UserDefaults.standard
        let previousLanguage = defaults.object(forKey: "appLanguage")
        defer {
            if let previousLanguage {
                defaults.set(previousLanguage, forKey: "appLanguage")
            } else {
                defaults.removeObject(forKey: "appLanguage")
            }
        }

        defaults.set("en", forKey: "appLanguage")
        XCTAssertEqual(AppLocalization.string("Save API key"), "Save API key")

        defaults.set("es", forKey: "appLanguage")
        XCTAssertEqual(AppLocalization.string("Save API key"), "Guardar clave API")

        defaults.set("de", forKey: "appLanguage")
        XCTAssertEqual(AppLocalization.string("Save API key"), "API-Schlüssel speichern")
    }
}
