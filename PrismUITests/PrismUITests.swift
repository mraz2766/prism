import AppIntents
import XCTest

@MainActor
final class PrismUITests: XCTestCase {
    func testDashboardLaunchesInUITestMode() {
        let app = launchApp()

        XCTAssertTrue(app.windows["Prism"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Network Exit"].waitForExistence(timeout: 5))
    }

    func testAppearanceNavigationAndAccentSelectionRemainInteractive() {
        let app = launchApp()
        XCTAssertTrue(app.windows["Prism"].waitForExistence(timeout: 8))

        app.typeKey(",", modifierFlags: .command)
        let appearance = app.buttons["Appearance"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 5))
        appearance.click()
        XCTAssertTrue(appearance.isSelected)

        let purple = app.buttons["Aurora Purple"]
        XCTAssertTrue(purple.waitForExistence(timeout: 3))
        purple.click()
        XCTAssertTrue(purple.isSelected)
        XCTAssertTrue(app.staticTexts["Aurora Purple"].exists)
        XCTAssertFalse(app.staticTexts["Live preview"].exists)
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()
        return app
    }
}
