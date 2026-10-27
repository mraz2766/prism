import AppKit
import SwiftUI

enum CountryFlag {
    static func normalizedCode(_ countryCode: String) -> String? {
        let code = countryCode.uppercased()
        guard code.count == 2,
              code.unicodeScalars.allSatisfy({ (65...90).contains($0.value) }) else {
            return nil
        }
        return code
    }

    static func emoji(for countryCode: String) -> String? {
        guard let code = normalizedCode(countryCode) else { return nil }
        let base: UInt32 = 0x1F1E6
        let scalars = code.unicodeScalars.compactMap { scalar in
            Unicode.Scalar(base + scalar.value - 65)
        }
        guard scalars.count == 2 else { return nil }
        return String(String.UnicodeScalarView(scalars))
    }

    static func image(for countryCode: String) -> NSImage? {
        CountryFlagImageCache.shared.image(for: countryCode, source: .circle)
    }

    static func cartoonImage(for countryCode: String) -> NSImage? {
        CountryFlagImageCache.shared.image(for: countryCode, source: .cartoon)
    }

    static func wavedImage(for countryCode: String) -> NSImage? {
        CountryFlagImageCache.shared.image(for: countryCode, source: .waved)
    }

    static func gradientImage(for countryCode: String) -> NSImage? {
        CountryFlagImageCache.shared.image(for: countryCode, source: .gradient)
    }

    static func squareImage(for countryCode: String) -> NSImage? {
        CountryFlagImageCache.shared.image(for: countryCode, source: .square)
    }

    static func roundedImage(for countryCode: String, targetWidth: CGFloat = 32) -> NSImage? {
        let source: CountryFlagAssetSource
        if targetWidth <= 18 {
            source = .roundedSmall
        } else if targetWidth <= 24 {
            source = .roundedMedium
        } else {
            source = .roundedLarge
        }
        return CountryFlagImageCache.shared.image(for: countryCode, source: source)
    }
}

struct CountryFlagView: View {
    let countryCode: String
    let style: CountryFlagStyle
    var diameter: CGFloat = 34
    var containerSize = CGSize(width: 48, height: 48)

    var body: some View {
        Group {
            switch style {
            case .emoji:
                Text(CountryFlag.emoji(for: countryCode) ?? "◎")
                    .font(.system(size: emojiFontSize))
            case .sticker:
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                    Circle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .padding(pixelAligned(max(2, min(containerSize.width, containerSize.height) * 0.08)))
                    circleFlag
                }
                .shadow(
                    color: .black.opacity(isCompact ? 0 : 0.08),
                    radius: isCompact ? 0 : 2,
                    y: isCompact ? 0 : 1
                )
            case .cartoon:
                cartoonFlag
            case .waved:
                wavedFlag
            case .gradient:
                gradientFlag
            case .rounded:
                roundedFlag
            case .square:
                squareFlag
            case .code:
                codeBadge
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .accessibilityLabel(accessibilityCountryName)
    }

    @ViewBuilder
    private var gradientFlag: some View {
        if let image = CountryFlag.gradientImage(for: countryCode) {
            let height = pixelAligned(diameter * 15 / 21)
            Image(nsImage: image)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(21 / 15, contentMode: .fit)
                .frame(width: diameter, height: height)
                .clipShape(RoundedRectangle(cornerRadius: max(2, height * 0.14), style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: max(2, height * 0.14), style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
                )
                .shadow(
                    color: .black.opacity(isCompact ? 0 : 0.08),
                    radius: isCompact ? 0 : 1,
                    y: isCompact ? 0 : 1
                )
        } else {
            circleFlag
        }
    }

    @ViewBuilder
    private var wavedFlag: some View {
        if let image = CountryFlag.wavedImage(for: countryCode) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(1, contentMode: .fit)
                .frame(width: diameter, height: diameter)
                .shadow(
                    color: .black.opacity(isCompact ? 0 : 0.10),
                    radius: isCompact ? 0 : 1,
                    y: isCompact ? 0 : 1
                )
        } else {
            circleFlag
        }
    }

    @ViewBuilder
    private var roundedFlag: some View {
        if let image = CountryFlag.roundedImage(for: countryCode, targetWidth: diameter) {
            let height = pixelAligned(diameter * 0.75)
            Image(nsImage: image)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(4 / 3, contentMode: .fit)
                .frame(width: diameter, height: height)
                .clipShape(RoundedRectangle(cornerRadius: max(2, height * 0.16), style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: max(2, height * 0.16), style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
                )
                .shadow(
                    color: .black.opacity(isCompact ? 0 : 0.08),
                    radius: isCompact ? 0 : 1,
                    y: isCompact ? 0 : 1
                )
        } else {
            circleFlag
        }
    }

    @ViewBuilder
    private var squareFlag: some View {
        if let image = CountryFlag.squareImage(for: countryCode) {
            let side = pixelAligned(diameter * 0.86)
            let cornerRadius = max(2, side * 0.22)
            Image(nsImage: image)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(1, contentMode: .fit)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
                )
                .shadow(
                    color: .black.opacity(isCompact ? 0 : 0.08),
                    radius: isCompact ? 0 : 1,
                    y: isCompact ? 0 : 1
                )
        } else {
            circleFlag
        }
    }

    private var codeBadge: some View {
        let height = pixelAligned(diameter * 0.62)
        return Text(CountryFlag.normalizedCode(countryCode) ?? "◎")
            .font(.system(size: height * 0.58, weight: .bold, design: .rounded))
            .monospaced()
            .foregroundStyle(Color.accentColor)
            .frame(width: diameter, height: height)
            .background(
                RoundedRectangle(cornerRadius: height * 0.28, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: height * 0.28, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 0.75)
            )
    }

    @ViewBuilder
    private var cartoonFlag: some View {
        if let image = CountryFlag.cartoonImage(for: countryCode) {
            ZStack(alignment: .bottomLeading) {
                Capsule()
                    .fill(Color(nsColor: .secondaryLabelColor).opacity(0.65))
                    .frame(
                        width: pixelAligned(max(1.5, diameter * 0.055)),
                        height: pixelAligned(diameter * 0.72)
                    )
                    .offset(
                        x: pixelAligned(diameter * 0.08),
                        y: pixelAligned(diameter * 0.06)
                    )

                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: diameter, height: pixelAligned(diameter * 0.64))
                    .clipped()
                    .rotationEffect(.degrees(isCompact ? 0 : -3), anchor: .bottomLeading)
                    .shadow(
                        color: .black.opacity(isCompact ? 0 : 0.12),
                        radius: isCompact ? 0 : 1,
                        y: isCompact ? 0 : 1
                    )
            }
            .frame(width: diameter, height: diameter)
        } else {
            circleFlag
        }
    }

    @ViewBuilder
    private var circleFlag: some View {
        if let image = CountryFlag.image(for: countryCode) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(1, contentMode: .fit)
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 0.5)
                )
        } else {
            ZStack {
                Circle().fill(Color(nsColor: .quaternaryLabelColor))
                Text(CountryFlag.normalizedCode(countryCode) ?? "◎")
                    .font(.system(size: diameter * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(width: diameter, height: diameter)
        }
    }

    private var accessibilityCountryName: String {
        let code = CountryFlag.normalizedCode(countryCode) ?? countryCode
        return Locale.autoupdatingCurrent.localizedString(forRegionCode: code) ?? code
    }

    private var isCompact: Bool {
        min(containerSize.width, containerSize.height) <= 32
    }

    private var emojiFontSize: CGFloat {
        (min(containerSize.width, containerSize.height) * 0.68).rounded()
    }

    private func pixelAligned(_ value: CGFloat) -> CGFloat {
        (value * 2).rounded() / 2
    }
}

private final class CountryFlagImageCache: @unchecked Sendable {
    static let shared = CountryFlagImageCache()
    private let cache = NSCache<NSString, NSImage>()

    func image(for countryCode: String, source: CountryFlagAssetSource) -> NSImage? {
        guard let code = CountryFlag.normalizedCode(countryCode)?.lowercased() else { return nil }
        let resourceName = source.resourcePrefix + code
        let key = "\(source.rawValue)/\(code)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let image: NSImage
        if let url = Self.resourceURL(resourceName, extension: "png", subdirectory: source.subdirectory),
           let bitmap = NSImage(contentsOf: url) {
            // 体积大的国旗集在构建前已按 rasterized 相同的规格预先栅格化为 PNG。
            image = bitmap
        } else if let url = Self.resourceURL(resourceName, extension: "svg", subdirectory: source.subdirectory),
                  let vector = NSImage(contentsOf: url) {
            // SVG 每次绘制都会重新矢量渲染，首次加载时栅格化为位图，
            // 之后菜单栏、列表和详情都只做位图缩放。
            image = Self.rasterized(vector)
        } else {
            return nil
        }
        image.isTemplate = false
        cache.setObject(image, forKey: key)
        return image
    }

    private static func resourceURL(_ name: String, extension ext: String, subdirectory: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
            ?? Bundle.main.url(forResource: name, withExtension: ext)
    }

    private static func rasterized(_ vector: NSImage, maximumPixelDimension: CGFloat = 176) -> NSImage {
        let size = vector.size
        guard size.width > 0, size.height > 0 else { return vector }
        let longestSide = max(size.width, size.height)
        let targetLongestSide = min(maximumPixelDimension, longestSide * 4)
        let scale = targetLongestSide / longestSide
        let pixelsWide = max(1, Int((size.width * scale).rounded(.up)))
        let pixelsHigh = max(1, Int((size.height * scale).rounded(.up)))
        guard let representation = NSBitmapImageRep(
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
        ), let context = NSGraphicsContext(bitmapImageRep: representation) else {
            return vector
        }
        // 上下文以像素为坐标（此时 representation.size 仍等于像素尺寸），
        // 因此按像素矩形绘制，绘制完成后再把点尺寸还原为原始尺寸。
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        vector.draw(
            in: NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        // 保持原始点尺寸，调用方基于源坐标的裁剪矩形（如卡通国旗）无需修改。
        representation.size = size

        let image = NSImage(size: size)
        image.addRepresentation(representation)
        return image
    }
}

private enum CountryFlagAssetSource: String {
    case circle
    case cartoon
    case waved
    case gradient
    case square
    case roundedSmall
    case roundedMedium
    case roundedLarge

    var resourcePrefix: String {
        switch self {
        case .circle: "circle-"
        case .cartoon: "cartoon-"
        case .waved: "wave-"
        case .gradient: "flagkit-"
        case .square: "square-"
        case .roundedSmall: "flagpack-s-"
        case .roundedMedium: "flagpack-m-"
        case .roundedLarge: "flagpack-l-"
        }
    }

    var subdirectory: String {
        switch self {
        case .circle: "CircleFlags"
        case .cartoon: "CartoonFlags"
        case .waved: "WavedFlags"
        case .gradient: "FlagKitFlags"
        case .square: "SquareFlags"
        case .roundedSmall, .roundedMedium, .roundedLarge: "FlagpackFlags"
        }
    }
}
