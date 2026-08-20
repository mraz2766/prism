import XCTest
@testable import Prism

final class CountryFlagTests: XCTestCase {
    func testNormalizesCountryCodeAndBuildsEmoji() {
        XCTAssertEqual(CountryFlag.normalizedCode("jp"), "JP")
        XCTAssertEqual(CountryFlag.emoji(for: "jp"), "🇯🇵")
    }

    func testRejectsInvalidCountryCode() {
        XCTAssertNil(CountryFlag.normalizedCode("JPN"))
        XCTAssertNil(CountryFlag.emoji(for: "1P"))
        XCTAssertNil(CountryFlag.image(for: "invalid"))
    }

    func testBundledCircleFlagCanBeLoaded() {
        XCTAssertNotNil(CountryFlag.image(for: "JP"))
    }
}
