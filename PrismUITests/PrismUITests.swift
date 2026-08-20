import AppIntents
import XCTest

@MainActor
final class PrismUITests: XCTestCase {
    func testDashboardLaunchesInUITestMode() {
        let app = launchApp()

        XCTAssertTrue(app.windows["Prism"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.network-exit-title"].waitForExistence(timeout: 5))
    }

    func testAppearanceNavigationAndAccentSelectionRemainInteractive() {
        let app = launchApp()
        XCTAssertTrue(app.windows["Prism"].waitForExistence(timeout: 8))

        app.typeKey(",", modifierFlags: .command)
        let appearance = app.buttons["settings.section.appearance"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 5))
        appearance.click()
        XCTAssertTrue(appearance.isSelected)

        let purple = app.buttons["settings.accent.auroraPurple"]
        XCTAssertTrue(purple.waitForExistence(timeout: 3))
        purple.click()
        XCTAssertTrue(purple.isSelected)
        XCTAssertTrue(app.descendants(matching: .any)["settings.accent.selection"].exists)
    }

    func testMenuBarIdentificationAndFlagStyleControlsAreAvailable() {
        let app = launchApp()
        XCTAssertTrue(app.windows["Prism"].waitForExistence(timeout: 8))

        app.typeKey(",", modifierFlags: .command)
        let menuBar = app.buttons["settings.section.menuBar"]
        XCTAssertTrue(menuBar.waitForExistence(timeout: 5))
        menuBar.click()

        XCTAssertTrue(app.descendants(matching: .any)["settings.menuBar.displayMode"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["settings.menuBar.flagStyle"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["settings.menuBar.preview"].waitForExistence(timeout: 3))
    }

    func testStatusItemSecondClickClosesPopover() {
        let app = launchApp()
        XCTAssertTrue(app.windows["Prism"].waitForExistence(timeout: 8))

        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))

        statusItem.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        let popover = app.descendants(matching: .any)["popover.ipv4-row"]
        XCTAssertTrue(popover.waitForExistence(timeout: 3))

        statusItem.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(popover.waitForNonExistence(timeout: 3))
    }

    func testHistoryRowOpensExitDetails() {
        let app = launchApp()
        XCTAssertTrue(app.windows["Prism"].waitForExistence(timeout: 8))

        app.radioButtons["clock.arrow.circlepath"].click()
        let firstEntry = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'history.entry.'"))
            .firstMatch
        XCTAssertTrue(firstEntry.waitForExistence(timeout: 3))

        firstEntry.click()
        XCTAssertTrue(app.descendants(matching: .any)["history.entry.detail"].waitForExistence(timeout: 3))
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
