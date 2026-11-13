import AppKit
import SwiftUI

enum CountryFlagEmblemStyle: Sendable {
    case postage
    case capsule

    var size: NSSize {
        NSSize(width: self == .postage ? 22 : 28, height: 18)
    }
}

/// 使用同一份绘制适配托盘与详情，避免预览和实际图标的比例、细节不同。
struct CountryFlagEmblemView: View {
    let countryCode: String
    let style: CountryFlagEmblemStyle
    var width: CGFloat? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let width = width ?? style.size.width
        let height = width * style.size.height / style.size.width
        if let image = CountryFlagEmblemImageFactory.image(
            for: countryCode, style: style, dark: colorScheme == .dark
        ) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: width, height: height)
        } else {
            Text("◎")
                .frame(width: width, height: height)
        }
    }
}

@MainActor
enum CountryFlagEmblemImageFactory {
    static func image(for countryCode: String, style: CountryFlagEmblemStyle, dark: Bool) -> NSImage? {
        guard let code = CountryFlag.normalizedCode(countryCode) else { return nil }
        let flag: NSImage? = switch style {
        case .postage: CountryFlag.gradientImage(for: code) ?? CountryFlag.image(for: code)
        case .capsule: CountryFlag.image(for: code) ?? CountryFlag.squareImage(for: code)
        }
        let image = NSImage(size: style.size, flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current?.imageInterpolation = .high
            switch style {
            case .postage:
                drawPostage(flag: flag, code: code, dark: dark)
            case .capsule:
                drawCapsule(flag: flag, code: code)
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func drawPostage(flag: NSImage?, code: String, dark: Bool) {
        let paperRect = NSRect(x: 1, y: 1.5, width: 20, height: 15)
        let outline = NSBezierPath(roundedRect: paperRect, xRadius: 0.6, yRadius: 0.6)
        let paper = outline.copy() as! NSBezierPath
        paper.windingRule = .evenOdd
        // 均匀的小半圆切口，保持四角完整；齿孔真正透明，不用背景色伪装。
        let radius: CGFloat = 0.45
        for index in 0..<8 {
            let x = paperRect.minX + (CGFloat(index) + 0.5) * paperRect.width / 8
            for y in [paperRect.minY, paperRect.maxY] {
                paper.appendOval(in: NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            }
        }
        for index in 0..<6 {
            let y = paperRect.minY + (CGFloat(index) + 0.5) * paperRect.height / 6
            for x in [paperRect.minX, paperRect.maxX] {
                paper.appendOval(in: NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            }
        }
        // 两层裁剪防止位于矩形外侧的半个齿孔被 even-odd 规则填回去。
        outline.addClip()
        paper.addClip()
        NSColor(calibratedWhite: dark ? 0.92 : 0.97, alpha: 1).setFill()
        paperRect.fill()
        NSColor(calibratedWhite: dark ? 0.56 : 0.62, alpha: 1).setStroke()
        paper.lineWidth = 0.5
        paper.stroke()

        let window = NSRect(x: 3, y: 3.25, width: 16, height: 11.5)
        let windowPath = NSBezierPath(roundedRect: window, xRadius: 0.3, yRadius: 0.3)
        NSColor.white.setFill()
        windowPath.fill()
        NSGraphicsContext.saveGraphicsState()
        windowPath.addClip()
        if let flag {
            drawFitted(flag, in: window)
        } else {
            drawCode(code, center: NSPoint(x: window.midX, y: window.midY), size: 8, color: .darkGray)
        }
        NSGraphicsContext.restoreGraphicsState()
        NSColor(calibratedWhite: 0.25, alpha: 0.2).setStroke()
        windowPath.lineWidth = 0.35
        windowPath.stroke()
    }

    private static func drawCapsule(flag: NSImage?, code: String) {
        // 比提案更窄、更薄：旗面有独立安全区，字母不压到右侧圆弧。
        let rect = NSRect(x: 1, y: 2.5, width: 26, height: 13)
        let capsule = NSBezierPath(roundedRect: rect, xRadius: 6.5, yRadius: 6.5)
        // 胶囊固定白底深色字，托盘与预览不再随外观反转配色。
        NSColor.white.setFill()
        capsule.fill()

        let flagRect = NSRect(x: 1.75, y: 3.25, width: 11.5, height: 11.5)
        let flagClip = NSBezierPath(ovalIn: flagRect)
        NSGraphicsContext.saveGraphicsState()
        flagClip.addClip()
        if let flag {
            drawFitted(flag, in: flagRect)
        } else {
            NSColor(calibratedWhite: 0.55, alpha: 1).setFill()
            flagRect.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.withAlphaComponent(0.18).setStroke()
        flagClip.lineWidth = 0.35
        flagClip.stroke()
        drawCode(
            code, center: NSPoint(x: 20, y: 9.15), size: 9,
            color: NSColor(calibratedWhite: 0.12, alpha: 1)
        )
        NSColor.black.withAlphaComponent(0.2).setStroke()
        capsule.lineWidth = 0.4
        capsule.stroke()
    }

    private static func drawFitted(_ image: NSImage, in rect: NSRect) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let scale = min(rect.width / image.size.width, rect.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(
            in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height),
            from: .zero, operation: .sourceOver, fraction: 1
        )
    }

    private static func drawCode(_ code: String, center: NSPoint, size: CGFloat, color: NSColor) {
        let text = NSAttributedString(string: code, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: .semibold),
            .foregroundColor: color,
            .kern: 0.1
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
    }
}
