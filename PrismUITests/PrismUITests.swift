import AppIntents
import XCTest

@MainActor
final class PrismUITests: XCTestCase {
    func testDashboardLaunchesInUITestMode() {
        let app = launchApp()

        XCTAssertTrue(app.windows["Prism"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.network-exit-title"].waitForExistence(timeout: 5))
    }

    func testLocationFailureKeepsConfirmedExitNormalInDashboard() {
        let app = launchApp(extraArguments: ["--ui-testing-location-unavailable"])
        app.activate()
        let dashboard = app.windows["Prism"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 8))
        XCTAssertTrue(dashboard.staticTexts["203.0.113.8"].firstMatch.waitForExistence(timeout: 5))
        let status = dashboard.descendants(matching: .any)["network.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        XCTAssertEqual(status.value as? String, "checkmark.circle.fill")
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.location-error"].exists)
        let country = dashboard.descendants(matching: .any)["location.country"]
        XCTAssertTrue(country.waitForExistence(timeout: 3))
        XCTAssertEqual(country.value as? String, "")
        attach(dashboard, named: "Confirmed exit remains normal without location data")
    }

    func testOfflineCountryRemainsVisibleWhenOnlineLocationFails() {
        let app = launchApp(extraArguments: ["--ui-testing-location-unavailable", "--ui-testing-offline-country"])
        app.activate()
        let dashboard = app.windows["Prism"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 8))
        XCTAssertTrue(dashboard.staticTexts["203.0.113.8"].firstMatch.waitForExistence(timeout: 5))
        let country = dashboard.descendants(matching: .any)["location.country"]
        XCTAssertTrue(country.waitForExistence(timeout: 3))
        XCTAssertEqual(country.value as? String, "JP")
        let source = dashboard.descendants(matching: .any)["location.source"]
        XCTAssertTrue(source.waitForExistence(timeout: 3))
        XCTAssertEqual(source.value as? String, "offline")
        XCTAssertEqual(dashboard.descendants(matching: .any)["network.status"].value as? String, "checkmark.circle.fill")
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.location-error"].exists)
        attach(dashboard, named: "Offline Japan country remains normal during online failure")
    }

    func testDomesticFallbackShowsChinaAndReachableDomesticExit() {
        let app = launchApp(extraArguments: ["--ui-testing-domestic-fallback", "--ui-testing-location-unavailable"])
        app.activate()
        let dashboard = app.windows["Prism"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 8))
        XCTAssertTrue(dashboard.staticTexts["198.51.100.86"].firstMatch.waitForExistence(timeout: 5))
        let country = dashboard.descendants(matching: .any)["location.country"]
        XCTAssertTrue(country.waitForExistence(timeout: 3))
        XCTAssertEqual(country.value as? String, "CN")
        XCTAssertEqual(dashboard.descendants(matching: .any)["exit.source"].value as? String, "domesticFallback")
        XCTAssertEqual(dashboard.descendants(matching: .any)["network.status"].value as? String, "checkmark.circle.fill")
        XCTAssertFalse(dashboard.staticTexts["203.0.113.8"].exists)
        attach(dashboard, named: "China domestic exit replaces unavailable overseas exit")
    }

    private func attach(_ element: XCUIElement, named name: String) {
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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

    private func launchApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ] + extraArguments
        app.launch()
        return app
    }
}
