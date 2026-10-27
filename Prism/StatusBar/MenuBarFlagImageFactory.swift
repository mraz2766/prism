import AppKit

/// 菜单栏使用的 18pt 高国旗图像；每种样式都有专门的紧凑绘制方式。
@MainActor
enum MenuBarFlagImageFactory {
    static func flagImage(for countryCode: String, style: CountryFlagStyle) -> NSImage? {
        switch style {
        case .cartoon:
            guard let source = CountryFlag.cartoonImage(for: countryCode) else { return nil }
            let size = NSSize(width: 18, height: 18)
            let image = NSImage(size: size, flipped: false) { rect in
                source.draw(
                    in: NSRect(x: 1, y: 3, width: 16, height: 12),
                    from: NSRect(x: 3, y: 15, width: 66, height: 42),
                    operation: .sourceOver,
                    fraction: 1
                )
                return true
            }
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
        case .rounded:
            guard let source = CountryFlag.roundedImage(for: countryCode, targetWidth: 16) else { return nil }
            return roundedImage(
                source,
                targetRect: NSRect(x: 1, y: 3, width: 16, height: 12),
                cornerRadius: 2
            )
        case .sticker:
            guard let source = CountryFlag.image(for: countryCode) else { return nil }
            let size = NSSize(width: 18, height: 18)
            let image = NSImage(size: size, flipped: false) { rect in
                NSColor.separatorColor.withAlphaComponent(0.58).setFill()
                NSBezierPath(ovalIn: rect).fill()
                source.draw(
                    in: rect.insetBy(dx: 1, dy: 1),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
                return true
            }
            image.isTemplate = false
            return image
        case .square:
            guard let source = CountryFlag.squareImage(for: countryCode) else { return nil }
            return roundedImage(
                source,
                targetRect: NSRect(x: 2, y: 2, width: 14, height: 14),
                cornerRadius: 3
            )
        case .code:
            return codeImage(for: countryCode)
        case .emoji:
            return emojiImage(for: countryCode)
        }
    }

    /// 国家代码徽章使用模板图，自动跟随菜单栏深浅色。
    static func codeImage(for countryCode: String) -> NSImage? {
        guard let code = CountryFlag.normalizedCode(countryCode) else { return nil }
        let attributed = NSAttributedString(
            string: code,
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .bold)]
        )
        let textSize = attributed.size()
        let size = NSSize(width: pixelAligned(textSize.width + 7), height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let badge = NSRect(x: 0.5, y: 3.5, width: rect.width - 1, height: 11)
            let path = NSBezierPath(roundedRect: badge, xRadius: 3, yRadius: 3)
            path.lineWidth = 1
            NSColor.black.setStroke()
            path.stroke()
            attributed.draw(at: NSPoint(
                x: pixelAligned((rect.width - textSize.width) / 2),
                y: pixelAligned(badge.midY - textSize.height / 2)
            ))
            return true
        }
        image.isTemplate = true
        return image
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
