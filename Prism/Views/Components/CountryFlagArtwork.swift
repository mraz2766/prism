import AppKit
import SwiftUI

/// 用代码绘制的特色国旗。
/// 菜单栏、弹窗、详情和设置预览共用同一份绘制，比例与细节完全一致。
enum CountryFlagArtworkStyle: Sendable {
    /// 12×9 的像素马赛克，四角削去一格，形成像素画的阶梯边缘。
    case pixel

    /// 宽高比（宽 / 高）。
    var aspectRatio: CGFloat {
        switch self {
        case .pixel: CGFloat(PixelGrid.columns) / CGFloat(PixelGrid.rows)
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
        }
    }

    /// 菜单栏 18pt 高画布：像素国旗每格 1.5pt（Retina 下正好 3 像素）。
    static func menuBarImage(for countryCode: String, style: CountryFlagArtworkStyle) -> NSImage? {
        let canvas = NSSize(width: 18, height: 18)
        let flagSize: NSSize = switch style {
        case .pixel: NSSize(width: 18, height: 13.5)
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
}
