import AppKit
import SwiftUI

enum CountryCodeBadgeStyle: Sendable {
    case colorBand
    case stamp
}

/// 托盘、设置预览和详情共用一份矢量绘制，尺寸变化只做等比缩放。
struct CountryCodeBadgeView: View {
    let countryCode: String
    let style: CountryCodeBadgeStyle
    var width: CGFloat = 28
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let image = CountryCodeBadgeImageFactory.image(
            for: countryCode, style: style, dark: colorScheme == .dark
        ) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: width, height: width * 18 / 28)
        } else {
            Text("◎")
                .frame(width: width, height: width * 18 / 28)
        }
    }
}

@MainActor
enum CountryCodeBadgeImageFactory {
    private static var paletteCache: [String: [NSColor]] = [:]

    static func image(for countryCode: String, style: CountryCodeBadgeStyle, dark: Bool) -> NSImage? {
        guard let code = CountryFlag.normalizedCode(countryCode) else { return nil }
        let colors = style == .colorBand ? palette(for: code) : []
        let image = NSImage(size: NSSize(width: 28, height: 18), flipped: false) { _ in
            let ink = dark ? NSColor.white : NSColor(calibratedWhite: 0.12, alpha: 1)
            // 印章额外留出旋转与粗描边的空间，避免在 18pt 高的托盘里切边。
            let rect = style == .stamp
                ? NSRect(x: 1.5, y: 2, width: 25, height: 14)
                : NSRect(x: 0.75, y: 1.5, width: 26.5, height: 15)
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            if style == .stamp {
                let transform = NSAffineTransform()
                transform.translateX(by: 14, yBy: 9)
                transform.rotate(byDegrees: 3)
                transform.translateX(by: -14, yBy: -9)
                transform.concat()
            }
            let radius: CGFloat = style == .stamp ? 2.5 : 4
            let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            if style == .colorBand {
                ink.withAlphaComponent(dark ? 0.13 : 0.055).setFill()
                path.fill()
                ink.withAlphaComponent(0.2).setStroke()
                path.lineWidth = 0.5
                path.stroke()
                NSGraphicsContext.saveGraphicsState()
                path.addClip()
                for (index, color) in colors.enumerated() {
                    color.setFill()
                    NSRect(
                        x: rect.minX + CGFloat(index) * rect.width / 3,
                        y: rect.minY, width: rect.width / 3, height: 2
                    ).fill()
                }
                NSGraphicsContext.restoreGraphicsState()
            } else {
                ink.setStroke()
                path.lineWidth = 1.55
                path.stroke()
            }
            let label = NSAttributedString(string: code, attributes: [
                .font: NSFont.monospacedSystemFont(
                    ofSize: style == .stamp ? 11 : 10.5,
                    weight: style == .stamp ? .heavy : .bold
                ),
                .foregroundColor: ink,
                .kern: style == .stamp ? 0.5 : 0.3
            ])
            let size = label.size()
            label.draw(at: NSPoint(
                x: (28 - size.width) / 2,
                y: (18 - size.height) / 2 + (style == .colorBand ? 0.8 : 0.2)
            ))
            return true
        }
        // 显式绘制当前外观的前景色，保留色带，并让叠加状态角标后的字母仍清楚可见。
        image.isTemplate = false
        return image
    }

    private static func palette(for code: String) -> [NSColor] {
        if let cached = paletteCache[code] { return cached }
        let red = NSColor(calibratedRed: 0.87, green: 0.12, blue: 0.22, alpha: 1)
        let colors: [NSColor]
        switch code {
        case "JP": colors = [.white, red, .white]
        case "US": colors = [NSColor(calibratedRed: 0.18, green: 0.32, blue: 0.66, alpha: 1), .white, red]
        case "CN": colors = [red, NSColor(calibratedRed: 1, green: 0.8, blue: 0, alpha: 1), red]
        default: colors = dominantColors(for: code)
        }
        paletteCache[code] = colors
        return colors
    }

    /// 从内置旗面提取代表色，覆盖其它国家和地区；缺少素材时使用中性色。
    private static func dominantColors(for code: String) -> [NSColor] {
        guard let image = CountryFlag.squareImage(for: code) ?? CountryFlag.image(for: code),
              let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first else {
            return Array(repeating: NSColor(calibratedWhite: 0.55, alpha: 1), count: 3)
        }
        var counts: [Int: Int] = [:]
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: max(1, bitmap.pixelsHigh / 32)) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: max(1, bitmap.pixelsWide / 32)) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.9 else { continue }
                let r = Int((color.redComponent * 7).rounded())
                let g = Int((color.greenComponent * 7).rounded())
                let b = Int((color.blueComponent * 7).rounded())
                counts[(r << 6) | (g << 3) | b, default: 0] += 1
            }
        }
        let ranked = counts.keys.sorted {
            let lhs = counts[$0, default: 0], rhs = counts[$1, default: 0]
            return lhs == rhs ? $0 < $1 : lhs > rhs
        }
        var colors: [NSColor] = []
        for key in ranked {
            let color = NSColor(
                calibratedRed: CGFloat((key >> 6) & 7) / 7,
                green: CGFloat((key >> 3) & 7) / 7,
                blue: CGFloat(key & 7) / 7, alpha: 1
            )
            let differs = colors.allSatisfy {
                abs($0.redComponent - color.redComponent)
                    + abs($0.greenComponent - color.greenComponent)
                    + abs($0.blueComponent - color.blueComponent) > 0.5
            }
            if differs { colors.append(color) }
            if colors.count == 3 { break }
        }
        if colors.isEmpty { colors.append(NSColor(calibratedWhite: 0.55, alpha: 1)) }
        while colors.count < 3 { colors.append(colors[0]) }
        return colors
    }
}
