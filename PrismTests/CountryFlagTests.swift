import AppKit
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

    func testBundledCartoonFlagCanBeLoaded() {
        XCTAssertNotNil(CountryFlag.cartoonImage(for: "CN"))
    }

    func testBundledWavedFlagCanBeLoaded() {
        XCTAssertNotNil(CountryFlag.wavedImage(for: "CN"))
    }

    func testBundledRoundedFlagCanBeLoaded() {
        XCTAssertNotNil(CountryFlag.roundedImage(for: "CN"))
    }

    func testBundledSquareFlagCanBeLoaded() {
        XCTAssertNotNil(CountryFlag.squareImage(for: "CN"))
    }

    func testBundledGradientFlagCanBeLoaded() {
        XCTAssertNotNil(CountryFlag.gradientImage(for: "CN"))
    }

    /// 栅格化后的国旗必须铺满整张位图，而不是缩在角落或被裁剪。
    func testRasterizedFlagsFillTheirBitmap() throws {
        let images: [(String, NSImage?, CGFloat, CGFloat)] = [
            ("circle", CountryFlag.image(for: "JP"), 0.9, 0.9),
            ("waved", CountryFlag.wavedImage(for: "JP"), 0.8, 0.5),
            ("gradient", CountryFlag.gradientImage(for: "JP"), 0.8, 0.6),
            ("rounded-s", CountryFlag.roundedImage(for: "JP", targetWidth: 16), 0.9, 0.9),
            ("rounded-m", CountryFlag.roundedImage(for: "JP", targetWidth: 20), 0.9, 0.9),
            ("rounded-l", CountryFlag.roundedImage(for: "JP", targetWidth: 32), 0.9, 0.9),
            ("square", CountryFlag.squareImage(for: "JP"), 0.9, 0.9),
            ("cartoon", CountryFlag.cartoonImage(for: "JP"), 0.8, 0.5)
        ]

        for (name, image, minimumWidth, minimumHeight) in images {
            let image = try XCTUnwrap(image, name)
            let bitmap = try XCTUnwrap(image.representations.first as? NSBitmapImageRep, name)
            var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            XCTAssertGreaterThanOrEqual(maxX, 0, "\(name) is empty")
            let coveredWidth = CGFloat(maxX - minX + 1) / CGFloat(bitmap.pixelsWide)
            let coveredHeight = CGFloat(maxY - minY + 1) / CGFloat(bitmap.pixelsHigh)
            XCTAssertGreaterThanOrEqual(coveredWidth, minimumWidth, "\(name) width coverage")
            XCTAssertGreaterThanOrEqual(coveredHeight, minimumHeight, "\(name) height coverage")
        }
    }
}
