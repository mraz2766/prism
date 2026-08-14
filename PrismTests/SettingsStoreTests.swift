import XCTest
@testable import Prism

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testAutomaticRefreshBindingPreservesValidConfiguration() throws {
        let suite = "PrismTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)

        XCTAssertEqual(settings.refreshInterval, .minute1)
        XCTAssertTrue(settings.automaticRefreshEnabled)

        settings.automaticRefreshEnabled = false
        XCTAssertEqual(settings.refreshInterval, .networkChangesOnly)
        XCTAssertTrue(settings.refreshConfiguration.refreshOnNetworkChange)

        settings.automaticRefreshEnabled = true
        XCTAssertEqual(settings.refreshInterval, .minute1)
    }

    func testAccentColorChoiceDefaultsAndPersists() throws {
        let suite = "PrismTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)

        XCTAssertEqual(settings.accentColorChoice, .prismBlue)

        settings.accentColorChoice = .sunsetOrange
        XCTAssertEqual(settings.accentColorChoice, .sunsetOrange)

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.accentColorChoice, .sunsetOrange)
    }

    func testDynamicAccentColorRuntimeInstallation() {
        DynamicAccentColorRuntime.install()
        DynamicAccentColorRuntime.apply(choice: .auroraPurple)
        XCTAssertNotNil(NSColor(named: "AccentColor"))
        XCTAssertNotNil(NSColor.controlAccentColor)
    }
}
