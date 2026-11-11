import XCTest
@testable import Prism

final class RegionGuardAndNotificationTests: XCTestCase {
    private func info(
        ipv4: String = "203.0.113.8",
        country: String,
        city: String? = nil,
        source: ExitSource = .overseasIPv4
    ) -> NetworkInfo {
        NetworkInfo(
            addresses: IPAddressSet(ipv4: ipv4, ipv6: nil),
            location: LocationInfo(countryCode: country, region: nil, city: city, timezone: nil, latitude: nil, longitude: nil),
            network: .unavailable,
            privacy: .unavailable,
            providerIdentifier: "test",
            exitSource: source,
            checkedAt: .now
        )
    }

    func testParsingAcceptsMixedSeparatorsAndDropsInvalidOrDuplicateCodes() {
        XCTAssertEqual(RegionGuard.parse("jp, US；sg、JP  usa 1x"), ["JP", "US", "SG"])
        XCTAssertEqual(RegionGuard.parse(""), [])
    }

    func testGuardOnlyFiresForIdentifiedCountriesOutsideTheList() {
        let rule = RegionGuard(isEnabled: true, expectedCountries: "JP, US")
        XCTAssertFalse(rule.isViolated(by: "jp"))
        XCTAssertTrue(rule.isViolated(by: "CN"))
        XCTAssertFalse(rule.isViolated(by: ""), "未识别国家时不应误报")
    }

    func testDisabledOrEmptyGuardNeverFires() {
        XCTAssertFalse(RegionGuard(isEnabled: false, expectedCountries: "JP").isViolated(by: "CN"))
        XCTAssertFalse(RegionGuard(isEnabled: true, expectedCountries: "  ").isViolated(by: "CN"))
    }

    func testGuardIgnoresUnconfirmedStatuses() {
        let rule = RegionGuard(isEnabled: true, expectedCountries: "JP")
        let china = info(country: "CN")
        XCTAssertTrue(rule.isViolated(by: .online(china)))
        XCTAssertFalse(rule.isViolated(by: .verifying(previous: china, candidateAddress: "198.51.100.1")))
        XCTAssertFalse(rule.isViolated(by: .stale(china, reason: .timeout)))
        XCTAssertFalse(rule.isViolated(by: .offline(previous: china)))
    }

    @MainActor
    func testChangeEventDistinguishesFallbackRecoveryAndPlainChange() {
        let tokyo = info(country: "JP")
        let osaka = info(ipv4: "203.0.113.9", country: "JP")
        let shanghai = info(ipv4: "198.51.100.86", country: "CN", source: .domesticFallback)
        XCTAssertEqual(AppEnvironment.changeEvent(from: tokyo, to: shanghai), .fellBackToDomestic(shanghai))
        XCTAssertEqual(AppEnvironment.changeEvent(from: shanghai, to: tokyo), .overseasRecovered(tokyo))
        XCTAssertEqual(AppEnvironment.changeEvent(from: tokyo, to: osaka), .exitChanged(from: tokyo, to: osaka))
    }

    func testChangeNotificationNamesBothPlacesAndTheNewAddress() {
        let locale = Locale(identifier: "en_US")
        let old = info(country: "JP", city: "Tokyo")
        let new = info(ipv4: "198.51.100.20", country: "US", city: "Los Angeles")
        let content = ExitNotificationContent.make(for: .exitChanged(from: old, to: new), locale: locale)
        XCTAssertTrue(content.body.contains("Japan · Tokyo → United States · Los Angeles"))
        XCTAssertTrue(content.body.hasSuffix("198.51.100.20"))
    }

    func testSamePlaceChangeStillShowsTheNewAddressInsteadOfAGenericSentence() {
        let locale = Locale(identifier: "en_US")
        let old = info(country: "JP", city: "Tokyo")
        let new = info(ipv4: "203.0.113.77", country: "JP", city: "Tokyo")
        let content = ExitNotificationContent.make(for: .exitChanged(from: old, to: new), locale: locale)
        XCTAssertEqual(content.body, "Japan · Tokyo\n203.0.113.77")
    }

    func testNotificationUsesTheSuppliedLocalizedCityName() {
        let new = info(country: "JP", city: "Tokyo")
        let content = ExitNotificationContent.make(
            for: .overseasRecovered(new),
            locale: Locale(identifier: "zh_CN"),
            cityName: { _ in "东京" }
        )
        XCTAssertTrue(content.body.contains("东京"))
        XCTAssertFalse(content.body.contains("Tokyo"))
    }

    func testRegionAlertListsTheExpectedCodes() {
        let content = ExitNotificationContent.make(
            for: .leftExpectedRegion(info(country: "CN"), expected: ["JP", "US"]),
            locale: Locale(identifier: "en_US")
        )
        XCTAssertTrue(content.body.contains("JP, US"))
        XCTAssertTrue(content.body.contains("China"))
    }
}
