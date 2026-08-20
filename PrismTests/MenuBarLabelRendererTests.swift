import XCTest
@testable import Prism

final class MenuBarLabelRendererTests: XCTestCase {
    func testAllDisplayModesStayCompactAndVisible() {
        for mode in MenuBarDisplayMode.allCases {
            let value = MenuBarLabelRenderer.presentation(
                status: .online(.preview),
                mode: mode,
                flagStyle: .sticker,
                customTemplate: "{status} {flag} {country} {city}"
            )
            XCTAssertLessThanOrEqual(value.title.count, 20)
            XCTAssertTrue(!value.title.isEmpty || value.indicator != .none)
        }
    }

    func testStickerFlagAndCodeUsesImageIndicator() {
        let value = MenuBarLabelRenderer.presentation(
            status: .online(.preview),
            mode: .flagAndCode,
            flagStyle: .sticker,
            customTemplate: ""
        )

        XCTAssertEqual(value, MenuBarPresentation(title: "CN", indicator: .flag(countryCode: "CN")))
    }

    func testEmojiFlagAndCodeStaysTextOnly() {
        let value = MenuBarLabelRenderer.presentation(
            status: .online(.preview),
            mode: .flagAndCode,
            flagStyle: .emoji,
            customTemplate: ""
        )

        XCTAssertEqual(value, MenuBarPresentation(title: "🇨🇳 CN", indicator: .none))
    }

    func testRouteAndCodeUsesCurrentRouteSymbol() {
        let value = MenuBarLabelRenderer.presentation(
            status: .online(.preview),
            mode: .routeAndCode,
            flagStyle: .sticker,
            customTemplate: ""
        )

        XCTAssertEqual(value.title, "CN")
        XCTAssertEqual(value.indicator, .systemSymbol(name: "point.3.connected.trianglepath.dotted"))
    }

    func testIconOnlyUsesCurrentRouteSymbolWithoutTitle() {
        let value = MenuBarLabelRenderer.presentation(
            status: .online(.preview),
            mode: .iconOnly,
            flagStyle: .sticker,
            customTemplate: ""
        )

        XCTAssertEqual(value.title, "")
        XCTAssertEqual(value.indicator, .systemSymbol(name: "point.3.connected.trianglepath.dotted"))
    }

    func testInvalidCustomTemplateFallsBackToDefault() {
        let value = MenuBarLabelRenderer.presentation(
            status: .online(.preview),
            mode: .custom,
            flagStyle: .sticker,
            customTemplate: "plain text without tokens",
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(value, MenuBarPresentation(title: "CN", indicator: .flag(countryCode: "CN")))
    }

    func testOfflineWithoutCacheIsExplicit() {
        let value = MenuBarLabelRenderer.presentation(
            status: .offline(previous: nil),
            mode: .flagAndCode,
            flagStyle: .sticker,
            customTemplate: ""
        )

        XCTAssertTrue(value.title.contains("—"))
    }

    func testEveryDisplayModeMakesVerificationVisible() {
        let status = NetworkStatus.verifying(previous: .preview, candidateAddress: "203.0.113.50")

        for mode in MenuBarDisplayMode.allCases {
            let value = MenuBarLabelRenderer.presentation(
                status: status,
                mode: mode,
                flagStyle: .sticker,
                customTemplate: "{flag} {country}"
            )
            let statusIsVisible = value.title.contains("◌")
                || value.indicator == .systemSymbol(name: status.symbolName)
            XCTAssertTrue(statusIsVisible, "Verification was hidden for \(mode)")
        }
    }

    func testCustomCityTokenUsesFullShortCity() {
        let value = MenuBarLabelRenderer.presentation(
            status: .online(.preview),
            mode: .custom,
            flagStyle: .sticker,
            customTemplate: "{city}"
        )

        XCTAssertEqual(value, MenuBarPresentation(title: "SH", indicator: .none))
    }

    func testCustomStickerFlagTokenUsesImageIndicator() {
        let value = MenuBarLabelRenderer.presentation(
            status: .online(.preview),
            mode: .custom,
            flagStyle: .sticker,
            customTemplate: "{flag} {code}"
        )

        XCTAssertEqual(value, MenuBarPresentation(title: "CN", indicator: .flag(countryCode: "CN")))
    }

    func testLongMultiwordCityUsesInitials() {
        XCTAssertEqual(MenuBarLabelRenderer.compactCityName("Hong Kong", fallback: "HK"), "HK")
    }

    func testHongKongWithoutSpaceUsesExpectedAbbreviation() {
        XCTAssertEqual(MenuBarLabelRenderer.compactCityName("hongkong", fallback: "HK"), "HK")
    }

    func testCityWithFiveLettersUsesFullName() {
        XCTAssertEqual(MenuBarLabelRenderer.compactCityName("Tokyo", fallback: "JP"), "Tokyo")
    }

    func testLongSingleWordCityUsesFirstTwoLetters() {
        XCTAssertEqual(MenuBarLabelRenderer.compactCityName("Singapore", fallback: "SG"), "SI")
    }

    func testNonLatinCityFallsBackToCountryCode() {
        XCTAssertEqual(MenuBarLabelRenderer.compactCityName("东京", fallback: "JP"), "JP")
    }

    func testDomesticEnglishCitiesUseTheSameLengthRule() {
        XCTAssertEqual(MenuBarLabelRenderer.compactCityName("Shanghai", fallback: "CN"), "SH")
        XCTAssertEqual(MenuBarLabelRenderer.compactCityName("Hangzhou", fallback: "CN"), "HA")
        XCTAssertEqual(MenuBarLabelRenderer.compactCityName("Yiwu", fallback: "CN"), "Yiwu")
    }
}
