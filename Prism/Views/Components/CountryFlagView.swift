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

        let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: "svg",
            subdirectory: source.subdirectory
        ) ?? Bundle.main.url(forResource: resourceName, withExtension: "svg")
        guard let url, let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = false
        cache.setObject(image, forKey: key)
        return image
    }
}

private enum CountryFlagAssetSource: String {
    case circle
    case cartoon
    case waved
    case gradient
    case roundedSmall
    case roundedMedium
    case roundedLarge

    var resourcePrefix: String {
        switch self {
        case .circle: ""
        case .cartoon: "cartoon-"
        case .waved: "wave-"
        case .gradient: "flagkit-"
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
        case .roundedSmall, .roundedMedium, .roundedLarge: "FlagpackFlags"
        }
    }
}
