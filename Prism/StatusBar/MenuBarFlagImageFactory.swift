import AppKit
import SwiftUI

/// 左侧增加 2pt 透明留白，让图标相对画布中心右移 1pt，并完整保留图案与角标。
@MainActor
enum MenuBarIconLayout {
    static let leadingPadding: CGFloat = 2

    static func alignedImage(_ source: NSImage) -> NSImage {
        let size = NSSize(width: source.size.width + leadingPadding, height: source.size.height)
        let image = NSImage(size: size, flipped: false) { _ in
            source.draw(
                in: NSRect(x: leadingPadding, y: 0, width: source.size.width, height: source.size.height),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            return true
        }
        image.isTemplate = source.isTemplate
        return image
    }
}

/// 菜单栏使用的 18pt 高国旗图像；每种样式都有专门的紧凑绘制方式。
@MainActor
enum MenuBarFlagImageFactory {
    static func flagImage(
        for countryCode: String,
        style: CountryFlagStyle,
        appearance: NSAppearance? = nil
    ) -> NSImage? {
        switch style {
        case .cartoon:
            // 与设置预览共用放大的卡通布局，保留旗杆和手绘倾斜。
            let colorScheme: ColorScheme = (appearance ?? NSApp.effectiveAppearance)
                .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
            let renderer = ImageRenderer(
                content: CountryFlagView.menuBarCartoon(for: countryCode)
                .environment(\.colorScheme, colorScheme)
            )
            renderer.scale = 2
            guard let image = renderer.nsImage else { return nil }
            image.isTemplate = false
            return image
        case .waved:
            guard let source = CountryFlag.wavedImage(for: countryCode) else { return nil }
            return fittedImage(source)
        case .gradient:
            guard let source = CountryFlag.gradientImage(for: countryCode) else { return nil }
            return roundedImage(
                source,
                targetRect: NSRect(x: 0, y: 2.5, width: 18, height: 13),
                cornerRadius: 2.5
            )
        case .square:
            guard let source = CountryFlag.squareImage(for: countryCode) else { return nil }
            return roundedImage(
                source,
                targetRect: NSRect(x: 2, y: 2, width: 14, height: 14),
                cornerRadius: 3
            )
        case .postage, .capsule:
            let dark = (appearance ?? NSApp.effectiveAppearance)
                .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return CountryFlagEmblemImageFactory.image(
                for: countryCode, style: style == .postage ? .postage : .capsule, dark: dark
            )
        case .code, .codeStamp:
            let dark = (appearance ?? NSApp.effectiveAppearance)
                .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return CountryCodeBadgeImageFactory.image(
                for: countryCode, style: style == .code ? .colorBand : .stamp, dark: dark
            )
        case .emoji:
            return emojiImage(for: countryCode)
        }
    }

    private static func fittedImage(_ source: NSImage) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func roundedImage(
        _ source: NSImage,
        targetRect: NSRect,
        cornerRadius: CGFloat
    ) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            let clipPath = NSBezierPath(
                roundedRect: targetRect,
                xRadius: cornerRadius,
                yRadius: cornerRadius
            )
            clipPath.addClip()
            source.draw(in: targetRect, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()

            NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
            clipPath.lineWidth = 0.5
            clipPath.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }

    static func emojiImage(for countryCode: String) -> NSImage? {
        guard let emoji = CountryFlag.emoji(for: countryCode) else { return nil }
        let size = NSSize(width: 20, height: 18)
        let attributed = NSAttributedString(
            string: emoji,
            attributes: [.font: NSFont.systemFont(ofSize: 14)]
        )
        let textSize = attributed.size()
        return NSImage(size: size, flipped: false) { _ in
            let origin = NSPoint(
                x: pixelAligned((size.width - textSize.width) / 2),
                y: pixelAligned((size.height - textSize.height) / 2)
            )
            attributed.draw(at: origin)
            return true
        }
    }

    private static func pixelAligned(_ value: CGFloat) -> CGFloat {
        (value * 2).rounded() / 2
    }
}
