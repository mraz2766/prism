import Foundation

enum MenuBarIndicator: Equatable {
    case none
    case flag(countryCode: String)
    case systemSymbol(name: String)
}

struct MenuBarPresentation: Equatable {
    let title: String
    let indicator: MenuBarIndicator
}

enum MenuBarLabelRenderer {
    static func presentation(
        status: NetworkStatus,
        mode: MenuBarDisplayMode,
        flagStyle: CountryFlagStyle,
        customTemplate: String,
        locale: Locale = .autoupdatingCurrent
    ) -> MenuBarPresentation {
        guard let info = status.info else {
            if mode == .iconOnly {
                return MenuBarPresentation(
                    title: "",
                    indicator: .systemSymbol(name: status.symbolName)
                )
            }
            return MenuBarPresentation(title: fallbackStatusLabel(status), indicator: .none)
        }

        let code = info.location.countryCode.uppercased()
        let flag = CountryFlag.emoji(for: code) ?? "◎"
        let country = info.location.localizedCountry(locale: locale)
        let city = compactCityName(info.location.city, fallback: code)
        let statusGlyph = glyph(for: status)
        let isOnline: Bool
        if case .online = status {
            isOnline = true
        } else {
            isOnline = false
        }

        var indicator: MenuBarIndicator = .none
        var value: String
        var alreadyShowsStatus = false

        switch mode {
        case .flagAndCode:
            if flagStyle == .emoji {
                value = "\(flag) \(code)"
            } else {
                indicator = .flag(countryCode: code)
                value = code
            }
        case .routeAndCode:
            indicator = .systemSymbol(name: isOnline ? routeSymbol(for: info.routeMode) : status.symbolName)
            value = code
            alreadyShowsStatus = !isOnline
        case .countryCode:
            value = code
        case .iconOnly:
            indicator = .systemSymbol(name: isOnline ? routeSymbol(for: info.routeMode) : status.symbolName)
            value = ""
            alreadyShowsStatus = true
        case .custom:
            let tokens = ["{flag}", "{country}", "{code}", "{city}", "{status}"]
            guard tokens.contains(where: customTemplate.contains) else {
                return presentation(
                    status: status,
                    mode: .flagAndCode,
                    flagStyle: flagStyle,
                    customTemplate: customTemplate,
                    locale: locale
                )
            }
            let flagValue: String
            if flagStyle == .emoji {
                flagValue = flag
            } else {
                flagValue = ""
                if customTemplate.contains("{flag}") {
                    indicator = .flag(countryCode: code)
                }
            }
            value = customTemplate
                .replacingOccurrences(of: "{flag}", with: flagValue)
                .replacingOccurrences(of: "{country}", with: country)
                .replacingOccurrences(of: "{code}", with: code)
                .replacingOccurrences(of: "{city}", with: city)
                .replacingOccurrences(of: "{status}", with: statusGlyph)
            alreadyShowsStatus = customTemplate.contains("{status}")
        }

        let trimmed = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let shouldPrefixStatus = !isOnline && !alreadyShowsStatus
        let finalTitle = shouldPrefixStatus
            ? [statusGlyph, trimmed].filter { !$0.isEmpty }.joined(separator: " ")
            : trimmed
        return MenuBarPresentation(
            title: truncate(finalTitle),
            indicator: indicator
        )
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

    static func routeSymbol(for routeMode: NetworkRouteMode) -> String {
        switch routeMode {
        case .proxy: "arrow.triangle.branch"
        case .direct: "point.3.connected.trianglepath.dotted"
        case .split: "arrow.triangle.swap"
        case .unknown: "network"
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
