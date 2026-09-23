import XCTest
@testable import Prism

final class LocalizedCityNameTests: XCTestCase {
    func testTokyoIsChineseImmediatelyInChineseInterface() {
        XCTAssertEqual(
            LocalizedCityName.chineseName(
                for: "Tokyo",
                countryCode: "JP",
                localizedCity: nil,
                locale: Locale(identifier: "zh_CN")
            ),
            "东京"
        )
    }

    func testLocalizedResultIsSimplifiedChinese() {
        XCTAssertEqual(
            LocalizedCityName.chineseName(
                for: "San Jose",
                countryCode: "US",
                localizedCity: "聖荷西",
                locale: Locale(identifier: "zh_CN")
            ),
            "圣荷西"
        )
    }

    func testEnglishInterfaceKeepsOriginalCity() {
        XCTAssertNil(
            LocalizedCityName.chineseName(
                for: "Tokyo",
                countryCode: "JP",
                localizedCity: "東京都",
                locale: Locale(identifier: "en_US")
            )
        )
    }
}
