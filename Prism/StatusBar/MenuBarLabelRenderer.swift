import Foundation

enum MenuBarIndicator: Equatable {
    case none
    case flag(countryCode: String)
    case emoji(countryCode: String)
    case systemSymbol(name: String)
}

/// 有国旗时把状态画成国旗右下角的小圆点，而不是在文字前加符号，避免菜单栏项宽度跳动。
enum MenuBarStatusBadge: String, Equatable, Sendable {
    case confirming
    case stale
    /// 出口落在期望地区之外。
    case guardAlert
}

struct MenuBarPresentation: Equatable {
    let title: String
    let indicator: MenuBarIndicator
    var badge: MenuBarStatusBadge? = nil
}

enum MenuBarLabelRenderer {
    static func presentation(
        status: NetworkStatus,
        mode: MenuBarDisplayMode,
        flagStyle: CountryFlagStyle,
        customTemplate: String,
        locale: Locale = .autoupdatingCurrent,
        cityOverride: String? = nil,
        outsideExpectedRegion: Bool = false
    ) -> MenuBarPresentation {
        guard let info = status.info else {
            if mode == .flagOnly {
                return MenuBarPresentation(
                    title: "",
                    indicator: .systemSymbol(name: status.symbolName)
                )
            }
            return MenuBarPresentation(title: fallbackStatusLabel(status), indicator: .none)
        }

        guard info.hasLocation else {
            return MenuBarPresentation(
                title: mode == .flagOnly ? "" : String(localized: "Country pending"),
                indicator: .systemSymbol(name: "globe"),
                badge: badge(for: status)
            )
        }

        let code = info.location.countryCode.uppercased()
        let country = info.location.localizedCountry(locale: locale)
        let city = menuBarCityName(info.location.city, override: cityOverride, fallback: code)
        let statusGlyph = glyph(for: status)
        let isOnline: Bool
        switch status {
        case .online, .locating, .locationUnavailable: isOnline = true
        default: isOnline = false
        }

        var indicator: MenuBarIndicator = .none
        var value: String
        var alreadyShowsStatus = false

        switch mode {
        case .flagAndCode:
            if flagStyle == .emoji {
                indicator = .emoji(countryCode: code)
                value = code
            } else {
                indicator = .flag(countryCode: code)
                value = code
            }
        case .flagAndCity:
            indicator = flagStyle == .emoji
                ? .emoji(countryCode: code)
                : .flag(countryCode: code)
            value = city
        case .countryCode:
            value = code
        case .flagOnly:
            indicator = flagStyle == .emoji
                ? .emoji(countryCode: code)
                : .flag(countryCode: code)
            value = ""
        case .custom:
            let tokens = ["{flag}", "{country}", "{code}", "{city}", "{status}"]
            guard tokens.contains(where: customTemplate.contains) else {
                return presentation(
                    status: status,
                    mode: .flagAndCode,
                    flagStyle: flagStyle,
                    customTemplate: customTemplate,
                    locale: locale,
                    cityOverride: cityOverride,
                    outsideExpectedRegion: outsideExpectedRegion
                )
            }
            let flagValue: String
            if flagStyle == .emoji {
                flagValue = ""
                if customTemplate.contains("{flag}") {
                    indicator = .emoji(countryCode: code)
                }
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
        let needsStatus = !isOnline && !alreadyShowsStatus
        let shouldPrefixStatus = needsStatus && indicator == .none
        let showsGuardAlert = outsideExpectedRegion && isOnline
        let finalTitle: String
        if shouldPrefixStatus {
            finalTitle = [statusGlyph, trimmed].filter { !$0.isEmpty }.joined(separator: " ")
        } else if showsGuardAlert && indicator == .none {
            // 没有国旗可挂角标时，用文字前缀提示越界。
            finalTitle = ["⚠︎", trimmed].filter { !$0.isEmpty }.joined(separator: " ")
        } else {
            finalTitle = trimmed
        }
        let resolvedBadge: MenuBarStatusBadge?
        if indicator == .none {
            resolvedBadge = nil
        } else if showsGuardAlert {
            resolvedBadge = .guardAlert
        } else {
            resolvedBadge = needsStatus ? badge(for: status) : nil
        }
        return MenuBarPresentation(
            title: truncate(finalTitle),
            indicator: indicator,
            badge: resolvedBadge
        )
    }

    /// 已本地化的城市名（如“东京”）直接显示；英文城市名仍走紧凑缩写。
    static func menuBarCityName(_ city: String?, override: String?, fallback: String) -> String {
        if let override = override?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty,
           override != city,
           override.unicodeScalars.contains(where: { $0.value > 0x2E7F }) {
            return override.count > 5 ? String(override.prefix(5)) : override
        }
        return compactCityName(city, fallback: fallback)
    }

    static func badge(for status: NetworkStatus) -> MenuBarStatusBadge? {
        switch status {
        case .loading, .verifying: .confirming
        case .online, .locating, .locationUnavailable, .stale, .offline, .idle, .failed: nil
        }
    }

    static func glyph(for status: NetworkStatus) -> String {
        switch status {
        case .online, .locating, .locationUnavailable: "●"
        case .loading, .verifying: "◌"
        case .offline: "—"
        case .stale: "◷"
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
        case .locating, .locationUnavailable: String(localized: "Online")
        case .verifying: "◌ " + String(localized: "Confirming new exit")
        case .offline: "— " + String(localized: "Offline")
        case .idle: "◌ " + String(localized: "Detecting")
        case .stale: "◷ " + String(localized: "Last confirmed")
        case .failed: "? " + String(localized: "Unknown")
        case .online: "? " + String(localized: "Unknown")
        }
    }

    private static func truncate(_ value: String) -> String {
        guard value.count > 20 else { return value }
        return String(value.prefix(19)) + "…"
    }
}

/// 自定义模板的结构化视图：国旗总是作为菜单栏图标显示在最前，其余元素按顺序组成文字。
enum MenuBarTemplateElement: String, CaseIterable, Identifiable, Sendable {
    case code
    case country
    case city
    case status

    var id: String { rawValue }
    var token: String { "{\(rawValue)}" }

    var label: String {
        switch self {
        case .code: String(localized: "Country code")
        case .country: String(localized: "Country name")
        case .city: String(localized: "City")
        case .status: String(localized: "Status dot")
        }
    }
}

struct MenuBarTemplateComposition: Equatable {
    var showsFlag: Bool
    var elements: [MenuBarTemplateElement]

    init(showsFlag: Bool, elements: [MenuBarTemplateElement]) {
        self.showsFlag = showsFlag
        self.elements = elements
    }

    init(template: String) {
        showsFlag = template.contains("{flag}")
        var found: [(String.Index, MenuBarTemplateElement)] = []
        for element in MenuBarTemplateElement.allCases {
            if let range = template.range(of: element.token) {
                found.append((range.lowerBound, element))
            }
        }
        elements = found.sorted { $0.0 < $1.0 }.map(\.1)
    }

    var isEmpty: Bool { !showsFlag && elements.isEmpty }

    /// 把 `element` 移到 `target` 之前；向后拖动时落在目标之后，符合拖拽的直觉。
    mutating func move(_ element: MenuBarTemplateElement, before target: MenuBarTemplateElement) {
        guard element != target,
              let from = elements.firstIndex(of: element),
              let to = elements.firstIndex(of: target) else { return }
        elements.remove(at: from)
        elements.insert(element, at: to)
    }

    var template: String {
        ((showsFlag ? ["{flag}"] : []) + elements.map(\.token)).joined(separator: " ")
    }

    /// 模板里是否含有结构化编辑无法表达的内容（自由文字、重复元素等）。
    static func isRepresentable(_ template: String) -> Bool {
        let normalized = template.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return normalized == MenuBarTemplateComposition(template: template).template
    }
}
