import AppIntents
import XCTest

@MainActor
final class PrismUITests: XCTestCase {
    func testDashboardLaunchesInUITestMode() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        XCTAssertTrue(app.windows["Prism"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Network Exit"].waitForExistence(timeout: 5))
    }
}
