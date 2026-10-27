import AppKit
import SwiftUI
import XCTest
@testable import Prism

/// 每种国旗样式在菜单栏与界面中都必须真正画出内容，防止资源或渲染改动悄悄失效。
@MainActor
final class FlagStyleRenderingTests: XCTestCase {
    private let countryCodes = ["JP", "CN", "US", "BR", "SV"]

    func testEveryStyleDrawsMenuBarImage() throws {
        for style in CountryFlagStyle.allCases {
            for code in countryCodes {
                let image = try XCTUnwrap(
                    MenuBarFlagImageFactory.flagImage(for: code, style: style),
                    "\(style) \(code)"
                )
                XCTAssertEqual(image.size.height, 18, "\(style) \(code) height")
                XCTAssertGreaterThan(Self.opaqueCoverage(of: image), 0.05, "\(style) \(code) is blank")
            }
        }
    }

    func testCountryCodeMenuBarImageIsTemplate() throws {
        let image = try XCTUnwrap(MenuBarFlagImageFactory.flagImage(for: "JP", style: .code))
        XCTAssertTrue(image.isTemplate)
        let flag = try XCTUnwrap(MenuBarFlagImageFactory.flagImage(for: "JP", style: .square))
        XCTAssertFalse(flag.isTemplate)
    }

    func testEveryStyleDrawsFlagView() throws {
        for style in CountryFlagStyle.allCases {
            for code in countryCodes {
                let renderer = ImageRenderer(
                    content: CountryFlagView(countryCode: code, style: style)
                        .environment(\.colorScheme, .light)
                )
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.nsImage, "\(style) \(code)")
                XCTAssertGreaterThan(Self.opaqueCoverage(of: image), 0.08, "\(style) \(code) is blank")
            }
        }
    }

    func testPrerenderedFlagSetsLoadAsBitmaps() throws {
        let images = [
            CountryFlag.wavedImage(for: "SV"),
            CountryFlag.squareImage(for: "SV"),
            CountryFlag.roundedImage(for: "SV", targetWidth: 16),
            CountryFlag.roundedImage(for: "SV", targetWidth: 32)
        ]
        for image in images {
            let image = try XCTUnwrap(image)
            XCTAssertTrue(image.representations.first is NSBitmapImageRep)
            XCTAssertGreaterThan(image.size.width, 0)
        }
    }

    /// 以 2x 位图计算非透明像素比例。
    private static func opaqueCoverage(of image: NSImage) -> CGFloat {
        let pixelsWide = max(1, Int(image.size.width * 2))
        let pixelsHigh = max(1, Int(image.size.height * 2))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return 0 }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
        NSGraphicsContext.restoreGraphicsState()
        var opaque = 0
        for y in 0..<pixelsHigh {
            for x in 0..<pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
                opaque += 1
            }
        }
        return CGFloat(opaque) / CGFloat(pixelsWide * pixelsHigh)
    }
}
