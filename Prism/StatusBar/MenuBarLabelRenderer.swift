import Foundation

enum CountryFlag {
    static func emoji(for countryCode: String) -> String? {
        let code = countryCode.uppercased()
        guard code.count == 2 else { return nil }
        let base: UInt32 = 0x1F1E6
        let scalars = code.unicodeScalars.compactMap { scalar -> Unicode.Scalar? in
            guard (65...90).contains(scalar.value) else { return nil }
            return Unicode.Scalar(base + scalar.value - 65)
        }
        guard scalars.count == 2 else { return nil }
        return String(String.UnicodeScalarView(scalars))
    }
}

enum MenuBarLabelRenderer {
    static func render(
        status: NetworkStatus,
        mode: MenuBarDisplayMode,
        customTemplate: String,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        guard let info = status.info else {
            return fallbackStatusLabel(status)
        }
        let flag = CountryFlag.emoji(for: info.location.countryCode) ?? "◎"
        let country = info.location.localizedCountry(locale: locale)
        let code = info.location.countryCode.uppercased()
        let city = compactCityName(info.location.city, fallback: code)
        let statusGlyph = glyph(for: status)

        let value: String
        switch mode {
        case .flag: value = flag
        case .flagAndCountry: value = "\(flag) \(country)"
        case .countryCode: value = code
        case .flagAndCode: value = "\(flag) \(code)"
        case .flagAndCity: value = "\(flag) \(city)"
        case .statusAndFlag: value = "\(statusGlyph) \(flag)"
        case .custom:
            let tokens = ["{flag}", "{country}", "{code}", "{city}", "{status}"]
            guard tokens.contains(where: customTemplate.contains) else {
                return truncate("\(flag) \(country)")
            }
            value = customTemplate
                .replacingOccurrences(of: "{flag}", with: flag)
                .replacingOccurrences(of: "{country}", with: country)
                .replacingOccurrences(of: "{code}", with: code)
                .replacingOccurrences(of: "{city}", with: city)
                .replacingOccurrences(of: "{status}", with: statusGlyph)
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldPrefixStatus: Bool = switch status {
        case .online: false
        case .idle, .loading, .verifying, .offline, .stale, .failed:
            mode != .statusAndFlag && !(mode == .custom && customTemplate.contains("{status}"))
        }
        return truncate(shouldPrefixStatus ? "\(statusGlyph) \(trimmed)" : trimmed)
    }

    static func glyph(for status: NetworkStatus) -> String {
        switch status {
        case .online: "●"
        case .loading, .verifying: "◌"
        case .offline: "—"
        case .stale: "!"
        case .idle, .failed: "?"
        }
    }

    static func compactCityName(_ city: String?, fallback: String) -> String {
        guard let city = city?.trimmingCharacters(in: .whitespacesAndNewlines),
              !city.isEmpty else { return fallback }

        let folded = city
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let words = folded.components(separatedBy: CharacterSet.letters.inverted).filter { word in
            !word.isEmpty && word.unicodeScalars.allSatisfy { scalar in
                (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
            }
        }
        let letterCount = words.reduce(0) { $0 + $1.count }
        guard letterCount >= 2 else { return fallback }
        if letterCount <= 5 { return city }
        if words.count > 1 {
            return String(words.prefix(2).compactMap(\.first)).uppercased()
        }
        if words[0].lowercased() == "hongkong" { return "HK" }
        return String(words[0].prefix(2)).uppercased()
    }

    private static func fallbackStatusLabel(_ status: NetworkStatus) -> String {
        switch status {
        case .loading: "◌ " + String(localized: "Detecting")
        case .verifying: "◌ " + String(localized: "Confirming new exit")
        case .offline: "— " + String(localized: "Offline")
        case .idle: "◌ " + String(localized: "Detecting")
        case .failed, .stale: "! " + String(localized: "Unknown")
        case .online: "? " + String(localized: "Unknown")
        }
    }

    private static func truncate(_ value: String) -> String {
        guard value.count > 20 else { return value }
        return String(value.prefix(19)) + "…"
    }
}
