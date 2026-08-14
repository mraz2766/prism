import AppKit
import SwiftUI
import XCTest
@testable import Prism

final class AccentThemeTests: XCTestCase {
    func testLegacyAccentRawValuesRemainStable() {
        XCTAssertEqual(AccentColorChoice.allCases.map(\.rawValue), [
            "prismBlue",
            "oceanicTeal",
            "sunsetOrange",
            "emeraldGreen",
            "auroraPurple",
            "graphite"
        ])
    }

    func testEveryAccentHasDistinctLightAndDarkVariants() {
        for choice in AccentColorChoice.allCases {
            XCTAssertNotEqual(choice.theme.light, choice.theme.dark, choice.rawValue)
        }
    }

    func testDynamicNSColorResolvesToThemeComponents() throws {
        let choice = AccentColorChoice.auroraPurple
        let lightAppearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        var lightColor: NSColor?
        var darkColor: NSColor?

        lightAppearance.performAsCurrentDrawingAppearance {
            lightColor = choice.nsColor.usingColorSpace(.sRGB)
        }
        darkAppearance.performAsCurrentDrawingAppearance {
            darkColor = choice.nsColor.usingColorSpace(.sRGB)
        }

        assert(
            try XCTUnwrap(lightColor),
            matches: choice.theme.light
        )
        assert(
            try XCTUnwrap(darkColor),
            matches: choice.theme.dark
        )
    }

    private func assert(
        _ color: NSColor,
        matches expected: Prism.RGBColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let converted = color.usingColorSpace(.sRGB) else {
            return XCTFail("Expected an sRGB color", file: file, line: line)
        }
        XCTAssertEqual(Double(converted.redComponent), expected.red, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(Double(converted.greenComponent), expected.green, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(Double(converted.blueComponent), expected.blue, accuracy: 0.001, file: file, line: line)
    }
}
