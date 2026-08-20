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
        CountryFlagImageCache.shared.image(for: countryCode)
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
                    .font(.system(size: min(containerSize.width, containerSize.height) * 0.68))
            case .circle:
                circleFlag
            case .sticker:
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                    Circle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .padding(max(2, min(containerSize.width, containerSize.height) * 0.08))
                    circleFlag
                }
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .accessibilityLabel(accessibilityCountryName)
    }

    @ViewBuilder
    private var circleFlag: some View {
        if let image = CountryFlag.image(for: countryCode) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
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
}

private final class CountryFlagImageCache: @unchecked Sendable {
    static let shared = CountryFlagImageCache()
    private let cache = NSCache<NSString, NSImage>()

    func image(for countryCode: String) -> NSImage? {
        guard let code = CountryFlag.normalizedCode(countryCode)?.lowercased() else { return nil }
        let key = code as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let url = Bundle.main.url(forResource: code, withExtension: "svg", subdirectory: "CircleFlags")
            ?? Bundle.main.url(forResource: code, withExtension: "svg")
        guard let url, let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = false
        cache.setObject(image, forKey: key)
        return image
    }
}
