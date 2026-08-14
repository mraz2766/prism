import XCTest
@testable import Prism

final class MenuBarLabelRendererTests: XCTestCase {
    func testAllDisplayModesStayCompact() {
        for mode in MenuBarDisplayMode.allCases {
            let value = MenuBarLabelRenderer.render(
                status: .online(.preview),
                mode: mode,
                customTemplate: "{status} {flag} {country} {city}"
            )
            XCTAssertLessThanOrEqual(value.count, 20)
            XCTAssertFalse(value.isEmpty)
        }
    }

    func testInvalidCustomTemplateFallsBack() {
        let value = MenuBarLabelRenderer.render(
            status: .online(.preview),
            mode: .custom,
            customTemplate: "plain text without tokens",
            locale: Locale(identifier: "en_US")
        )
        XCTAssertEqual(value, "🇯🇵 Japan")
    }

    func testOfflineWithoutCacheIsExplicit() {
        let value = MenuBarLabelRenderer.render(
            status: .offline(previous: nil),
            mode: .flagAndCountry,
            customTemplate: ""
        )
        XCTAssertTrue(value.contains("—"))
    }

    func testEveryDisplayModeMakesVerificationVisible() {
        let status = NetworkStatus.verifying(
            previous: .preview,
            candidateAddress: "203.0.113.50"
        )

        for mode in MenuBarDisplayMode.allCases {
            let value = MenuBarLabelRenderer.render(
                status: status,
                mode: mode,
                customTemplate: "{flag} {country}"
            )
            XCTAssertTrue(value.contains("◌"), "Verification was hidden for \(mode)")
        }
    }

    func testCityDisplayUsesCompactKnownCode() {
        let value = MenuBarLabelRenderer.render(
            status: .online(.preview),
            mode: .flagAndCity,
            customTemplate: ""
        )

        XCTAssertEqual(value, "🇯🇵 Tokyo")
    }

    func testCustomCityTokenUsesCompactCode() {
        let value = MenuBarLabelRenderer.render(
            status: .online(.preview),
            mode: .custom,
            customTemplate: "{city}"
        )

        XCTAssertEqual(value, "Tokyo")
    }

    func testLongMultiwordCityUsesInitials() {
        XCTAssertEqual(
            MenuBarLabelRenderer.compactCityName("Hong Kong", fallback: "HK"),
            "HK"
        )
    }

    func testHongKongWithoutSpaceUsesExpectedAbbreviation() {
        XCTAssertEqual(
            MenuBarLabelRenderer.compactCityName("hongkong", fallback: "HK"),
            "HK"
        )
    }

    func testCityWithFiveLettersUsesFullName() {
        XCTAssertEqual(
            MenuBarLabelRenderer.compactCityName("Tokyo", fallback: "JP"),
            "Tokyo"
        )
    }

    func testLongSingleWordCityUsesFirstTwoLetters() {
        XCTAssertEqual(
            MenuBarLabelRenderer.compactCityName("Singapore", fallback: "SG"),
            "SI"
        )
    }

    func testNonLatinCityFallsBackToCountryCode() {
        XCTAssertEqual(
            MenuBarLabelRenderer.compactCityName("东京", fallback: "JP"),
            "JP"
        )
    }


    func testDomesticEnglishCitiesUseTheSameLengthRule() {
        XCTAssertEqual(MenuBarLabelRenderer.compactCityName("Shanghai", fallback: "CN"), "SH")
        XCTAssertEqual(MenuBarLabelRenderer.compactCityName("Hangzhou", fallback: "CN"), "HA")
        XCTAssertEqual(MenuBarLabelRenderer.compactCityName("Yiwu", fallback: "CN"), "Yiwu")
    }
}
