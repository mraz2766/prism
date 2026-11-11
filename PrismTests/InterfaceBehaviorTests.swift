import XCTest
@testable import Prism

final class InterfaceBehaviorTests: XCTestCase {
    private func tokyo() -> NetworkInfo {
        NetworkInfo(
            addresses: IPAddressSet(ipv4: "203.0.113.8", ipv6: nil),
            location: LocationInfo(countryCode: "JP", region: nil, city: "Tokyo", timezone: nil, latitude: nil, longitude: nil),
            network: .unavailable,
            privacy: .unavailable,
            providerIdentifier: "test",
            checkedAt: .now
        )
    }

    // MARK: 菜单栏

    func testGuardAlertBadgesTheFlagOnlyWhileTheExitIsConfirmed() {
        let info = tokyo()
        let online = MenuBarLabelRenderer.presentation(
            status: .online(info), mode: .flagAndCode, flagStyle: .sticker,
            customTemplate: "", outsideExpectedRegion: true
        )
        XCTAssertEqual(online.badge, .guardAlert)
        XCTAssertEqual(online.title, "JP")

        let verifying = MenuBarLabelRenderer.presentation(
            status: .verifying(previous: info, candidateAddress: "198.51.100.1"),
            mode: .flagAndCode, flagStyle: .sticker,
            customTemplate: "", outsideExpectedRegion: true
        )
        XCTAssertEqual(verifying.badge, .confirming)
    }

    func testGuardAlertFallsBackToATextPrefixWithoutAFlag() {
        let value = MenuBarLabelRenderer.presentation(
            status: .online(tokyo()), mode: .countryCode, flagStyle: .sticker,
            customTemplate: "", outsideExpectedRegion: true
        )
        XCTAssertNil(value.badge)
        XCTAssertEqual(value.title, "⚠︎ JP")
    }

    func testLocalizedCityReplacesTheAbbreviationInTheMenuBar() {
        let localized = MenuBarLabelRenderer.presentation(
            status: .online(tokyo()), mode: .flagAndCity, flagStyle: .sticker,
            customTemplate: "", cityOverride: "东京"
        )
        XCTAssertEqual(localized.title, "东京")

        let untouched = MenuBarLabelRenderer.presentation(
            status: .online(tokyo()), mode: .flagAndCity, flagStyle: .sticker,
            customTemplate: "", cityOverride: "Tokyo"
        )
        XCTAssertEqual(untouched.title, "Tokyo")
    }

    func testDraggingAChipMovesItToTheDropTarget() {
        var forward = MenuBarTemplateComposition(showsFlag: true, elements: [.code, .country, .city])
        forward.move(.code, before: .city)
        XCTAssertEqual(forward.elements, [.country, .city, .code])

        var backward = MenuBarTemplateComposition(showsFlag: true, elements: [.code, .country, .city])
        backward.move(.city, before: .code)
        XCTAssertEqual(backward.elements, [.city, .code, .country])

        var unchanged = MenuBarTemplateComposition(showsFlag: true, elements: [.code, .country])
        unchanged.move(.status, before: .code)
        XCTAssertEqual(unchanged.elements, [.code, .country])
    }

    // MARK: 动画与时间

    func testRefreshGlyphFinishesTheCurrentRevolutionInsteadOfRewinding() {
        let start = Date(timeIntervalSince1970: 0)
        let stopRequested = start.addingTimeInterval(1.0)
        let end = RefreshGlyph.completionDate(startedAt: start, now: stopRequested)
        XCTAssertEqual(end.timeIntervalSince(start), 1.6, accuracy: 0.0001)

        let midway = RefreshGlyph.angle(at: start.addingTimeInterval(1.2), startedAt: start, stopAt: end)
        XCTAssertEqual(midway, 180, accuracy: 0.001)
        XCTAssertEqual(RefreshGlyph.angle(at: end, startedAt: start, stopAt: end), 0)
        XCTAssertEqual(RefreshGlyph.angle(at: start, startedAt: nil, stopAt: nil), 0)
    }

    func testStoppingImmediatelyStillCompletesOneFullTurn() {
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(
            RefreshGlyph.completionDate(startedAt: start, now: start).timeIntervalSince(start),
            0.8,
            accuracy: 0.0001
        )
    }

    func testConfirmedTimeStaysQuietDuringTheFirstMinute() {
        let now = Date(timeIntervalSince1970: 10_000)
        let fresh = ConfirmedTimeText.label(for: now.addingTimeInterval(-5), now: now)
        let alsoFresh = ConfirmedTimeText.label(for: now.addingTimeInterval(-59), now: now)
        let older = ConfirmedTimeText.label(for: now.addingTimeInterval(-180), now: now)
        XCTAssertEqual(fresh, alsoFresh, "一分钟内文字不应变化")
        XCTAssertNotEqual(fresh, older)
    }

    @MainActor
    func testLatencyIsSmoothedAndRoundedToFiveMilliseconds() {
        let model = ProbeLatencyModel()
        XCTAssertNil(model.milliseconds)
        model.record(.milliseconds(123))
        XCTAssertEqual(model.milliseconds, 125)
        model.record(.milliseconds(223))
        XCTAssertEqual(model.milliseconds, 165)
        model.reset()
        XCTAssertNil(model.milliseconds)
        XCTAssertEqual(ProbeLatencyModel.quality(for: 120), .good)
        XCTAssertEqual(ProbeLatencyModel.quality(for: 400), .fair)
        XCTAssertEqual(ProbeLatencyModel.quality(for: 900), .poor)
    }

    // MARK: 城市本地化

    @MainActor
    func testCityLocalizerSharesOneTranslationAcrossTheInterface() async throws {
        let suite = "prism.tests.city.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let info = NetworkInfo(
            addresses: IPAddressSet(ipv4: "203.0.113.8", ipv6: nil),
            location: LocationInfo(countryCode: "US", region: nil, city: "San Jose", timezone: nil, latitude: nil, longitude: nil),
            network: .unavailable,
            privacy: .unavailable,
            providerIdentifier: "test",
            checkedAt: .now,
            locationCheckedAt: .now,
            locationSource: .online
        )
        let localizer = CityLocalizer(
            defaults: defaults,
            locale: { Locale(identifier: "zh_CN") },
            lookup: { _ in ("US", "聖荷西") }
        )
        XCTAssertEqual(localizer.displayCity(for: info), "San Jose")

        localizer.resolveIfNeeded(for: .online(info))
        for _ in 0..<200 where localizer.names.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(localizer.displayCity(for: info), "圣荷西")
        // 历史记录只有国家代码与英文城市名，也应得到同一译名。
        XCTAssertEqual(localizer.displayCity("san jose", countryCode: "us"), "圣荷西")
        // 译名落盘后，新实例无需再次联网。
        let reloaded = CityLocalizer(defaults: defaults, locale: { Locale(identifier: "zh_CN") }, lookup: nil)
        XCTAssertEqual(reloaded.displayCity(for: info), "圣荷西")
    }

    @MainActor
    func testCityLocalizerLeavesEnglishInterfacesUntouched() throws {
        let suite = "prism.tests.city.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["JP|osaka": "大阪"], forKey: "cityLocalizer.zhNames")
        let localizer = CityLocalizer(defaults: defaults, locale: { Locale(identifier: "en_US") }, lookup: nil)
        XCTAssertEqual(localizer.displayCity("Osaka", countryCode: "JP"), "Osaka")
        XCTAssertNil(localizer.displayCity(nil, countryCode: "JP"))
    }
}
