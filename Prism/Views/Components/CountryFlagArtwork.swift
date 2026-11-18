import AppKit
import SwiftUI

/// 用代码绘制的特色国旗。
/// 菜单栏、弹窗、详情和设置预览共用同一份绘制，比例与细节完全一致。
enum CountryFlagArtworkStyle: Sendable {
    /// 12×9 的像素马赛克，四角削去一格，形成像素画的阶梯边缘。
    case pixel
    /// 印在暖白哑光纸上的国旗贴纸，右下角折起，露出纸背与折痕。
    case foldedSticker

    /// 宽高比（宽 / 高）。
    var aspectRatio: CGFloat {
        switch self {
        case .pixel: CGFloat(PixelGrid.columns) / CGFloat(PixelGrid.rows)
        case .foldedSticker: 4.0 / 3.0
        }
    }
}

enum PixelGrid {
    static let columns = 12
    static let rows = 9

    /// 四个角各削去一格。
    static func isCornerCell(column: Int, row: Int) -> Bool {
        (column == 0 || column == columns - 1) && (row == 0 || row == rows - 1)
    }
}

struct CountryFlagArtworkView: View {
    let countryCode: String
    let style: CountryFlagArtworkStyle
    /// 旗面宽度；高度按样式比例换算。
    let width: CGFloat

    var body: some View {
        let height = width / style.aspectRatio
        if let image = CountryFlagArtworkFactory.image(
            for: countryCode,
            style: style,
            size: NSSize(width: width, height: height)
        ) {
            Image(nsImage: image)
                .resizable()
                .interpolation(style == .pixel ? .none : .high)
                .frame(width: width, height: height)
        } else {
            Text(CountryFlag.normalizedCode(countryCode) ?? "◎")
                .font(.system(size: height * 0.42, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: width, height: height)
        }
    }
}

@MainActor
enum CountryFlagArtworkFactory {
    private static var paletteCache: [String: [[NSColor]]] = [:]
    private static let neutralPalette = Array(
        repeating: Array(repeating: NSColor(calibratedWhite: 0.62, alpha: 1), count: PixelGrid.columns),
        count: PixelGrid.rows
    )

    /// 生成指定点尺寸的国旗图像；绘制回调按实际显示尺寸重绘，任何尺寸都清晰。
    static func image(for countryCode: String, style: CountryFlagArtworkStyle, size: NSSize) -> NSImage? {
        guard let code = CountryFlag.normalizedCode(countryCode) else { return nil }
        switch style {
        case .pixel:
            // 没有对应素材的地区（如 ZZ）退回中性灰马赛克，仍保留像素轮廓。
            let palette = pixelPalette(for: code) ?? Self.neutralPalette
            let image = NSImage(size: size, flipped: true) { rect in
                drawPixel(palette: palette, in: rect)
                return true
            }
            image.isTemplate = false
            return image
        case .foldedSticker:
            let flag = CountryFlag.gradientImage(for: code) ?? CountryFlag.squareImage(for: code)
            let image = NSImage(size: size, flipped: false) { rect in
                drawFoldedSticker(flag: flag, code: code, in: rect)
                return true
            }
            image.isTemplate = false
            return image
        }
    }

    /// 菜单栏 18pt 高画布：像素国旗每格 1.5pt（Retina 下正好 3 像素）；贴纸占满 24×18pt。
    static func menuBarImage(for countryCode: String, style: CountryFlagArtworkStyle) -> NSImage? {
        let canvas: NSSize = switch style {
        case .pixel: NSSize(width: 18, height: 18)
        case .foldedSticker: NSSize(width: 24, height: 18)
        }
        let flagSize: NSSize = switch style {
        case .pixel: NSSize(width: 18, height: 13.5)
        case .foldedSticker: canvas
        }
        guard let flag = image(for: countryCode, style: style, size: flagSize) else { return nil }
        let image = NSImage(size: canvas, flipped: false) { _ in
            NSGraphicsContext.current?.imageInterpolation = style == .pixel ? .none : .high
            flag.draw(
                in: NSRect(
                    x: (canvas.width - flagSize.width) / 2,
                    y: (canvas.height - flagSize.height) / 2,
                    width: flagSize.width,
                    height: flagSize.height
                ),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: 像素国旗

    /// 把矩形国旗缩小到 12×9 取色；同一国家只取一次。
    static func pixelPalette(for code: String) -> [[NSColor]]? {
        if let cached = paletteCache[code] { return cached }
        guard let source = CountryFlag.gradientImage(for: code) ?? CountryFlag.squareImage(for: code),
              let bitmap = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: PixelGrid.columns,
                  pixelsHigh: PixelGrid.rows,
                  bitsPerSample: 8,
                  samplesPerPixel: 4,
                  hasAlpha: true,
                  isPlanar: false,
                  colorSpaceName: .deviceRGB,
                  bytesPerRow: 0,
                  bitsPerPixel: 0
              ),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // 高质量缩小相当于对每格区域取平均色，细节（如星星、徽章）会自然融进色块。
        context.imageInterpolation = .high
        source.draw(
            in: NSRect(x: 0, y: 0, width: PixelGrid.columns, height: PixelGrid.rows),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        var palette: [[NSColor]] = []
        for row in 0..<PixelGrid.rows {
            var line: [NSColor] = []
            for column in 0..<PixelGrid.columns {
                // NSBitmapImageRep 的 y 从上往下，与 palette 的行序一致。
                line.append(bitmap.colorAt(x: column, y: row) ?? .gray)
            }
            palette.append(line)
        }
        paletteCache[code] = palette
        return palette
    }

    private static func drawPixel(palette: [[NSColor]], in rect: NSRect) {
        let cellWidth = rect.width / CGFloat(PixelGrid.columns)
        let cellHeight = rect.height / CGFloat(PixelGrid.rows)
        func cellRect(_ column: Int, _ row: Int) -> NSRect {
            NSRect(
                x: rect.minX + CGFloat(column) * cellWidth,
                y: rect.minY + CGFloat(row) * cellHeight,
                width: cellWidth,
                height: cellHeight
            )
        }
        func isFilled(_ column: Int, _ row: Int) -> Bool {
            column >= 0 && column < PixelGrid.columns && row >= 0 && row < PixelGrid.rows
                && !PixelGrid.isCornerCell(column: column, row: row)
        }

        // 每格边缘对齐到设备像素并关闭抗锯齿，色块之间不会出现发丝缝或格线。
        let context = NSGraphicsContext.current?.cgContext
        let scale = context.map { $0.userSpaceToDeviceSpaceTransform.a } ?? 2
        func snap(_ value: CGFloat) -> CGFloat { (value * abs(scale)).rounded() / abs(scale) }
        context?.saveGState()
        context?.setShouldAntialias(false)
        for row in 0..<PixelGrid.rows {
            let top = snap(rect.minY + CGFloat(row) * cellHeight)
            let bottom = snap(rect.minY + CGFloat(row + 1) * cellHeight)
            for column in 0..<PixelGrid.columns where isFilled(column, row) {
                let left = snap(rect.minX + CGFloat(column) * cellWidth)
                let right = snap(rect.minX + CGFloat(column + 1) * cellWidth)
                (palette[row][column].usingColorSpace(.deviceRGB) ?? .gray).withAlphaComponent(1).setFill()
                NSRect(x: left, y: top, width: right - left, height: bottom - top).fill()
            }
        }
        context?.restoreGState()

        // 沿阶梯外轮廓描一圈细边，白色旗面在浅色菜单栏上也有边界。
        let outline = NSBezierPath()
        for row in 0..<PixelGrid.rows {
            for column in 0..<PixelGrid.columns where isFilled(column, row) {
                let cell = cellRect(column, row)
                if !isFilled(column, row - 1) {
                    outline.move(to: NSPoint(x: cell.minX, y: cell.minY))
                    outline.line(to: NSPoint(x: cell.maxX, y: cell.minY))
                }
                if !isFilled(column, row + 1) {
                    outline.move(to: NSPoint(x: cell.minX, y: cell.maxY))
                    outline.line(to: NSPoint(x: cell.maxX, y: cell.maxY))
                }
                if !isFilled(column - 1, row) {
                    outline.move(to: NSPoint(x: cell.minX, y: cell.minY))
                    outline.line(to: NSPoint(x: cell.minX, y: cell.maxY))
                }
                if !isFilled(column + 1, row) {
                    outline.move(to: NSPoint(x: cell.maxX, y: cell.minY))
                    outline.line(to: NSPoint(x: cell.maxX, y: cell.maxY))
                }
            }
        }
        NSColor.black.withAlphaComponent(0.28).setStroke()
        outline.lineWidth = max(0.5, min(cellWidth, cellHeight) * 0.18)
        outline.stroke()
    }

    // MARK: 折角贴纸

    /// 纸张配色：正面是偏暖的米白，背面略深略黄，像普通铜版纸的反面。
    private enum Paper {
        static let face = NSColor(calibratedRed: 0.985, green: 0.968, blue: 0.93, alpha: 1)
        static let backLight = NSColor(calibratedRed: 0.95, green: 0.925, blue: 0.87, alpha: 1)
        static let backDark = NSColor(calibratedRed: 0.84, green: 0.80, blue: 0.72, alpha: 1)
        static let edge = NSColor(calibratedRed: 0.55, green: 0.49, blue: 0.40, alpha: 0.35)
    }

    /// 贴纸外形：右下角沿折痕剪掉一个三角。
    static func stickerOutline(_ rect: NSRect, radius: CGFloat, fold: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX + radius, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX - fold, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY + fold))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - radius))
        path.appendArc(withCenter: NSPoint(x: rect.maxX - radius, y: rect.maxY - radius), radius: radius, startAngle: 0, endAngle: 90)
        path.line(to: NSPoint(x: rect.minX + radius, y: rect.maxY))
        path.appendArc(withCenter: NSPoint(x: rect.minX + radius, y: rect.maxY - radius), radius: radius, startAngle: 90, endAngle: 180)
        path.line(to: NSPoint(x: rect.minX, y: rect.minY + radius))
        path.appendArc(withCenter: NSPoint(x: rect.minX + radius, y: rect.minY + radius), radius: radius, startAngle: 180, endAngle: 270)
        path.close()
        return path
    }

    private static func drawFoldedSticker(flag: NSImage?, code: String, in rect: NSRect) {
        let s = rect.height
        // 下方多留一点给投影，左右留出贴纸外缘。
        let body = NSRect(
            x: rect.minX + s * 0.05,
            y: rect.minY + s * 0.1,
            width: rect.width - s * 0.1,
            height: s * 0.82
        )
        let radius = s * 0.06
        let fold = min(body.width, body.height) * 0.36
        let paper = stickerOutline(body, radius: radius, fold: fold)

        // 1. 纸张投影：柔和、偏下，像贴在桌面上。
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedRed: 0.25, green: 0.2, blue: 0.12, alpha: 0.28)
        shadow.shadowBlurRadius = s * 0.05
        shadow.shadowOffset = NSSize(width: 0, height: -s * 0.03)
        shadow.set()
        Paper.face.setFill()
        paper.fill()
        NSGraphicsContext.restoreGraphicsState()

        // 2. 旗面：以正片叠底印在纸上，白色部分就是纸色，看起来是印刷而不是贴图。
        let margin = s * 0.075
        let printRect = body.insetBy(dx: margin, dy: margin)
        let printArea = stickerOutline(printRect, radius: radius * 0.5, fold: max(0, fold - margin * 1.4))
        NSGraphicsContext.saveGraphicsState()
        printArea.addClip()
        if let flag {
            NSGraphicsContext.current?.imageInterpolation = .high
            flag.draw(in: printRect, from: .zero, operation: .multiply, fraction: 0.94)
        } else {
            NSColor(calibratedWhite: 0.6, alpha: 1).setFill()
            printRect.fill(using: .multiply)
            let text = NSAttributedString(string: code, attributes: [
                .font: NSFont.systemFont(ofSize: s * 0.36, weight: .bold),
                .foregroundColor: Paper.face
            ])
            let size = text.size()
            text.draw(at: NSPoint(x: printRect.midX - size.width / 2, y: printRect.midY - size.height / 2))
        }
        NSGraphicsContext.restoreGraphicsState()

        // 3. 纸纹：固定种子的细小明暗点，同一国家每次都一样；尺寸较小时自动稀疏。
        NSGraphicsContext.saveGraphicsState()
        paper.addClip()
        drawGrain(in: body, seed: code, scale: s)
        // 纸面左上受光、右下略暗的哑光渐变，没有高光。
        NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.10),
            NSColor(calibratedRed: 0.4, green: 0.32, blue: 0.2, alpha: 0.06)
        ])?.draw(in: body, angle: -35)
        NSGraphicsContext.restoreGraphicsState()

        // 4. 折痕附近的阴影：翻起的纸角在正面投下一道柔和的影子。
        let creaseStart = NSPoint(x: body.maxX - fold, y: body.minY)
        let creaseEnd = NSPoint(x: body.maxX, y: body.minY + fold)
        NSGraphicsContext.saveGraphicsState()
        paper.addClip()
        let shade = NSBezierPath()
        let depth = fold * 0.42
        shade.move(to: creaseStart)
        shade.line(to: creaseEnd)
        shade.line(to: NSPoint(x: creaseEnd.x - depth, y: creaseEnd.y))
        shade.line(to: NSPoint(x: creaseStart.x, y: creaseStart.y + depth))
        shade.close()
        shade.addClip()
        NSGradient(colors: [
            NSColor(calibratedRed: 0.3, green: 0.24, blue: 0.14, alpha: 0.26),
            NSColor(calibratedRed: 0.3, green: 0.24, blue: 0.14, alpha: 0)
        ])?.draw(
            from: NSPoint(x: (creaseStart.x + creaseEnd.x) / 2, y: (creaseStart.y + creaseEnd.y) / 2),
            to: NSPoint(x: (creaseStart.x + creaseEnd.x) / 2 - depth * 0.7, y: (creaseStart.y + creaseEnd.y) / 2 + depth * 0.7),
            options: []
        )
        NSGraphicsContext.restoreGraphicsState()

        // 5. 翻起的纸角：剪掉的那块沿折痕翻到正面，边缘略带弧度，露出纸背。
        let tip = NSPoint(x: body.maxX - fold * 0.86, y: body.minY + fold * 0.86)
        let flap = NSBezierPath()
        flap.move(to: creaseStart)
        flap.curve(
            to: tip,
            controlPoint1: NSPoint(x: creaseStart.x - fold * 0.04, y: creaseStart.y + fold * 0.42),
            controlPoint2: NSPoint(x: tip.x - fold * 0.02, y: tip.y - fold * 0.18)
        )
        flap.curve(
            to: creaseEnd,
            controlPoint1: NSPoint(x: tip.x + fold * 0.18, y: tip.y + fold * 0.02),
            controlPoint2: NSPoint(x: creaseEnd.x - fold * 0.42, y: creaseEnd.y + fold * 0.04)
        )
        flap.close()
        NSGraphicsContext.saveGraphicsState()
        let flapShadow = NSShadow()
        flapShadow.shadowColor = NSColor(calibratedRed: 0.25, green: 0.2, blue: 0.12, alpha: 0.3)
        flapShadow.shadowBlurRadius = s * 0.035
        flapShadow.shadowOffset = NSSize(width: -s * 0.015, height: s * 0.01)
        flapShadow.set()
        Paper.backLight.setFill()
        flap.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        flap.addClip()
        // 纸背从折痕处较亮，往尖角方向逐渐变暗，模拟纸张的弯曲。
        NSGradient(colors: [Paper.backLight, Paper.backDark])?.draw(
            from: NSPoint(x: (creaseStart.x + creaseEnd.x) / 2, y: (creaseStart.y + creaseEnd.y) / 2),
            to: tip,
            options: []
        )
        drawGrain(in: flap.bounds, seed: code + "-back", scale: s)
        NSGraphicsContext.restoreGraphicsState()

        // 6. 折痕：一条很细的亮线，再加纸张外缘的暖灰细边。
        let crease = NSBezierPath()
        crease.move(to: creaseStart)
        crease.line(to: creaseEnd)
        NSColor.white.withAlphaComponent(0.7).setStroke()
        crease.lineWidth = max(0.4, s * 0.012)
        crease.stroke()

        Paper.edge.setStroke()
        paper.lineWidth = max(0.4, s * 0.012)
        paper.stroke()
        flap.lineWidth = max(0.4, s * 0.01)
        flap.stroke()
    }

    /// 细小的纸纹噪点：固定种子，保证菜单栏刷新时纹理不闪烁。
    private static func drawGrain(in rect: NSRect, seed: String, scale: CGFloat) {
        guard scale >= 14 else { return }
        var state = seed.unicodeScalars.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1.value)) &* 1099511628211 }
        func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((state >> 33) & 0xFFFF) / CGFloat(0xFFFF)
        }
        let count = min(700, Int(rect.width * rect.height * 0.28))
        let dot = max(0.35, scale * 0.012)
        for _ in 0..<count {
            let x = rect.minX + next() * rect.width
            let y = rect.minY + next() * rect.height
            let dark = next() < 0.55
            (dark
                ? NSColor(calibratedRed: 0.35, green: 0.28, blue: 0.18, alpha: 0.035 + next() * 0.04)
                : NSColor.white.withAlphaComponent(0.05 + next() * 0.06)
            ).setFill()
            NSRect(x: x, y: y, width: dot, height: dot).fill()
        }
    }
}
