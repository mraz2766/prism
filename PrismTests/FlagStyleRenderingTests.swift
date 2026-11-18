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
                let source = try XCTUnwrap(
                    MenuBarFlagImageFactory.flagImage(for: code, style: style),
                    "\(style) \(code)"
                )
                let image = MenuBarIconLayout.alignedImage(source)
                XCTAssertEqual(image.isTemplate, source.isTemplate)
                XCTAssertEqual(image.size.height, 18, "\(style) \(code) height")
                XCTAssertGreaterThan(Self.opaqueCoverage(of: image), 0.05, "\(style) \(code) is blank")
            }
        }
    }

    func testCodeBadgeColorBandsAndMonochromeStampSurviveBothAppearances() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            for code in ["JP", "US", "CN", "BR"] {
                for style in [CountryFlagStyle.code, .codeStamp] {
                    let image = try XCTUnwrap(MenuBarFlagImageFactory.flagImage(
                        for: code, style: style, appearance: appearance
                    ))
                    XCTAssertEqual(image.size, NSSize(width: 28, height: 18))
                    XCTAssertFalse(image.isTemplate, "Preserve explicit colors when a status badge is added")
                    let bitmap = try XCTUnwrap(Self.bitmap(of: image))
                    if style == .code {
                        let background = try XCTUnwrap(bitmap.colorAt(x: 8, y: 12)?.usingColorSpace(.deviceRGB))
                        XCTAssertGreaterThan(background.alphaComponent, 0.99, "Menu bar background must not show through")
                        for channel in [background.redComponent, background.greenComponent, background.blueComponent] {
                            XCTAssertGreaterThan(channel, 0.9)
                            XCTAssertLessThan(channel, 0.99)
                        }
                    }
                    let usesLightLetters = style == .codeStamp && name == .darkAqua
                    var coloredBandPixels = 0
                    var contrastingLetterPixels = 0
                    for y in 0..<bitmap.pixelsHigh {
                        for x in 0..<bitmap.pixelsWide {
                            let pixel = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                            guard pixel.alphaComponent > 0.8 else { continue }
                            let channels = [pixel.redComponent, pixel.greenComponent, pixel.blueComponent]
                            let saturation = (channels.max() ?? 0) - (channels.min() ?? 0)
                            if saturation > 0.3, y >= 28 { coloredBandPixels += 1 }
                            if (12..<44).contains(x), (8..<26).contains(y), saturation < 0.1,
                               usesLightLetters ? pixel.redComponent > 0.8 : pixel.redComponent < 0.2 {
                                contrastingLetterPixels += 1
                            }
                        }
                    }
                    if style == .code {
                        XCTAssertGreaterThan(coloredBandPixels, 10, "\(code) lost its national colors")
                    } else {
                        XCTAssertEqual(coloredBandPixels, 0, "Stamp should remain monochrome")
                    }
                    XCTAssertGreaterThan(contrastingLetterPixels, 30, "\(style) \(code) lost readable letters")
                }
            }
        }
    }

    func testCartoonPoleRemainsVisibleBelowFlagOnLightAndDarkMenuBars() throws {
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            for code in ["JP", "CN", "US"] {
                let source = try XCTUnwrap(MenuBarFlagImageFactory.flagImage(
                    for: code, style: .cartoon, appearance: appearance
                ))
                let image = MenuBarIconLayout.alignedImage(source)
                let bitmap = try XCTUnwrap(Self.bitmap(of: image))
                // 2x 图像中，旗面下方必须留下连续、清晰的旗杆，而非仅有顶部一小点。
                for y in 31...33 {
                    let pole = try XCTUnwrap(bitmap.colorAt(x: 10, y: y)?.usingColorSpace(.deviceRGB))
                    XCTAssertGreaterThan(pole.alphaComponent, 0.8, "\(code) pole at \(y)")
                    if appearanceName == .darkAqua {
                        XCTAssertGreaterThan(pole.redComponent, 0.8, "Pole must contrast with a dark menu bar")
                    } else {
                        XCTAssertLessThan(pole.redComponent, 0.2, "Pole must contrast with a light menu bar")
                    }
                    XCTAssertLessThan(bitmap.colorAt(x: 20, y: y)?.alphaComponent ?? 1, 0.1)
                }
            }
        }
    }

    func testMenuBarAlignmentPreservesEdgesAndTemplateBehavior() throws {
        for isTemplate in [false, true] {
            let source = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
                NSColor.black.setFill()
                rect.fill()
                return true
            }
            source.isTemplate = isTemplate
            let image = MenuBarIconLayout.alignedImage(source)
            XCTAssertEqual(image.size, NSSize(width: 20, height: 18))
            XCTAssertEqual(image.isTemplate, isTemplate)
            let bitmap = try XCTUnwrap(Self.bitmap(of: image))
            // 满幅原图必须完整保留，左侧新增留白，右边缘不得被截掉。
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
                    if x < 4 {
                        XCTAssertLessThan(alpha, 0.01)
                    } else {
                        XCTAssertGreaterThan(alpha, 0.99)
                    }
                }
            }
        }
    }

    func testCompactEmblemsPreserveFlagProportionsAndNativeSizes() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            for style in [CountryFlagStyle.capsule] {
                let image = try XCTUnwrap(MenuBarFlagImageFactory.flagImage(
                    for: "JP", style: style, appearance: appearance
                ))
                XCTAssertEqual(image.size, NSSize(width: 28, height: 18))
                let bitmap = try XCTUnwrap(Self.bitmap(of: image))
                var minX = bitmap.pixelsWide, minY = bitmap.pixelsHigh, maxX = -1, maxY = -1
                for y in 0..<bitmap.pixelsHigh {
                    for x in 0..<bitmap.pixelsWide {
                        let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                        if color.alphaComponent > 0.8, color.redComponent > 0.5,
                           color.greenComponent < 0.35, color.blueComponent < 0.45 {
                            minX = min(minX, x); maxX = max(maxX, x)
                            minY = min(minY, y); maxY = max(maxY, y)
                        }
                    }
                }
                XCTAssertGreaterThan(maxX - minX, 3, "Japanese disc must remain visible")
                XCTAssertLessThanOrEqual(abs((maxX - minX) - (maxY - minY)), 1, "Flag disc must not become an ellipse")
            }
        }
    }

    func testPixelFlagUsesSteppedCornersAndCrispCells() throws {
        let image = try XCTUnwrap(MenuBarFlagImageFactory.flagImage(for: "JP", style: .pixel))
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        let bitmap = try XCTUnwrap(Self.bitmap(of: image))
        // 旗面 18×13.5pt 居中：上下各留 2.25pt；左上角那一格被削去，应透明。
        // 削去的角格只剩相邻描边的抗锯齿，远低于实色格。
        XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 1, y: 6)).alphaComponent, 0.3)
        XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 5, y: 6)).alphaComponent, 0.9)
        XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 17, y: 1)).alphaComponent, 0.01)

        let palette = try XCTUnwrap(CountryFlagArtworkFactory.pixelPalette(for: "JP"))
        XCTAssertEqual(palette.count, PixelGrid.rows)
        XCTAssertEqual(palette[0].count, PixelGrid.columns)
        let center = try XCTUnwrap(palette[4][6].usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(center.redComponent, 0.6, "Japanese disc must survive pixelation")
        XCTAssertLessThan(center.greenComponent, 0.4)
        let edge = try XCTUnwrap(palette[1][1].usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(min(edge.redComponent, edge.greenComponent, edge.blueComponent), 0.85)
    }

    func testFoldedStickerPrintsOnPaperWithAFoldedCorner() throws {
        let image = try XCTUnwrap(MenuBarFlagImageFactory.flagImage(for: "JP", style: .foldedSticker))
        XCTAssertEqual(image.size, NSSize(width: 24, height: 18))
        let bitmap = try XCTUnwrap(Self.bitmap(of: image))
        // 旗面中心是印上去的红圆。
        let disc = try XCTUnwrap(bitmap.colorAt(x: 20, y: 17)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(disc.redComponent, 0.6)
        XCTAssertLessThan(disc.greenComponent, 0.35)
        // 白色部分是偏暖的纸色，而不是纯白。
        let paper = try XCTUnwrap(bitmap.colorAt(x: 6, y: 9)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(paper.alphaComponent, 0.99)
        XCTAssertGreaterThan(paper.redComponent, paper.blueComponent + 0.02, "Paper should be warm, not pure white")
        // 右下角被折起：最角落的位置没有纸。
        XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 46, y: 31)).alphaComponent, 0.3)
        // 相同国家两次绘制完全一致，纸纹不会在菜单栏刷新时闪烁。
        let again = try XCTUnwrap(MenuBarFlagImageFactory.flagImage(for: "JP", style: .foldedSticker))
        XCTAssertEqual(Self.bitmap(of: again)?.tiffRepresentation, bitmap.tiffRepresentation)
    }

    func testRemovedStylesMigrateToTheDefaultFlag() throws {
        for legacy in ["waved", "postage", "emoji", "orb"] {
            let suite = "prism.tests.flag-migration.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(legacy, forKey: "menuBar.flagStyle")
            XCTAssertEqual(SettingsStore(defaults: defaults).countryFlagStyle, .gradient, legacy)
        }
    }

    func testCapsuleLettersStayReadableAndMissingFlagsHaveFallbacks() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            for code in ["JP", "US", "CN", "WW", "ZZ"] {
                let image = try XCTUnwrap(MenuBarFlagImageFactory.flagImage(
                    for: code, style: .capsule, appearance: NSAppearance(named: name)
                ))
                let bitmap = try XCTUnwrap(Self.bitmap(of: image))
                let body = try XCTUnwrap(bitmap.colorAt(x: 34, y: 7)?.usingColorSpace(.deviceRGB))
                XCTAssertGreaterThan(body.alphaComponent, 0.99)
                XCTAssertGreaterThan(min(body.redComponent, body.greenComponent, body.blueComponent), 0.98)
                var letterPixels = 0
                for y in 10..<26 {
                    for x in 29..<50 {
                        let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                        if color.alphaComponent > 0.9, color.redComponent < 0.3 {
                            letterPixels += 1
                        }
                    }
                }
                XCTAssertGreaterThan(letterPixels, 20, "\(code) capsule letters lost their contrast")
            }
        }
        for style in [CountryFlagStyle.capsule, .pixel, .foldedSticker] {
            XCTAssertNil(MenuBarFlagImageFactory.flagImage(for: "invalid", style: style))
            let fallback = try XCTUnwrap(MenuBarFlagImageFactory.flagImage(for: "ZZ", style: style))
            XCTAssertGreaterThan(Self.opaqueCoverage(of: fallback), 0.1)
        }
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
            CountryFlag.squareImage(for: "SV"),
        ]
        for image in images {
            let image = try XCTUnwrap(image)
            XCTAssertTrue(image.representations.first is NSBitmapImageRep)
            XCTAssertGreaterThan(image.size.width, 0)
        }
    }

    /// 固定以 2x 绘制，避免惰性 NSImage 的 TIFF 默认分辨率影响像素断言。
    private static func bitmap(of image: NSImage) -> NSBitmapImageRep? {
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
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private static func opaqueCoverage(of image: NSImage) -> CGFloat {
        guard let bitmap = bitmap(of: image) else { return 0 }
        var opaque = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
                opaque += 1
            }
        }
        return CGFloat(opaque) / CGFloat(bitmap.pixelsWide * bitmap.pixelsHigh)
    }
}
