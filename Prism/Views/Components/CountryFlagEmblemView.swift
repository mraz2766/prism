import AppKit
import SwiftUI

enum CountryFlagEmblemStyle: Sendable {
    case capsule

    var size: NSSize { NSSize(width: 28, height: 18) }
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
        let flag = CountryFlag.image(for: code) ?? CountryFlag.squareImage(for: code)
        let image = NSImage(size: style.size, flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current?.imageInterpolation = .high
            drawCapsule(flag: flag, code: code)
            return true
        }
        image.isTemplate = false
        return image
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
