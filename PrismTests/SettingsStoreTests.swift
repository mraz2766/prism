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

    func testUnrelatedSettingsDoNotEmitRefreshConfiguration() async throws {
        let suite = "PrismTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        var changes = settings.changes().makeAsyncIterator()

        let initial = await changes.next()
        XCTAssertEqual(initial, settings.refreshConfiguration)
        settings.accentColorChoice = .auroraPurple
        settings.menuBarDisplayMode = .iconOnly
        settings.countryFlagStyle = .rounded
        settings.appearanceMode = .dark
        settings.refreshInterval = .minutes5

        let refreshChange = await changes.next()
        XCTAssertEqual(
            refreshChange,
            RefreshConfiguration(interval: .minutes5, refreshOnNetworkChange: true)
        )
    }

    func testFlagStyleDefaultsAndPersists() throws {
        let suite = "PrismTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.countryFlagStyle, .sticker)

        settings.countryFlagStyle = .waved
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.countryFlagStyle, .waved)
    }

    func testLegacyMenuBarModesMigrateToFlagAndCode() throws {
        let legacyModes = ["flag", "flagAndCountry", "flagAndCity", "statusAndFlag"]

        for legacyMode in legacyModes {
            let suite = "PrismTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(legacyMode, forKey: "menuBar.displayMode")

            let settings = SettingsStore(defaults: defaults)
            XCTAssertEqual(settings.menuBarDisplayMode, .flagAndCode, "Failed to migrate \(legacyMode)")
        }
    }

    func testDraftFlagStylesMigrateToCircleDesigns() throws {
        let expectedStyles: [String: CountryFlagStyle] = [
            "flat": .sticker,
            "badge": .sticker,
            "circle": .sticker
        ]

        for (legacyStyle, expectedStyle) in expectedStyles {
            let suite = "PrismTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(legacyStyle, forKey: "menuBar.flagStyle")

            XCTAssertEqual(SettingsStore(defaults: defaults).countryFlagStyle, expectedStyle)
        }
    }

    func testAssigningSameRefreshValueDoesNotEmitDuplicate() async throws {
        let suite = "PrismTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        var changes = settings.changes().makeAsyncIterator()

        _ = await changes.next()
        settings.refreshInterval = .minutes5
        let intervalChange = await changes.next()
        XCTAssertEqual(intervalChange?.interval, .minutes5)
        settings.refreshInterval = .minutes5
        settings.refreshOnNetworkChange = false

        let networkChange = await changes.next()
        XCTAssertEqual(
            networkChange,
            RefreshConfiguration(interval: .minutes5, refreshOnNetworkChange: false)
        )
    }
}
