import SwiftUI

enum RefreshInterval: Int, CaseIterable, Codable, Identifiable, Sendable {
    case networkChangesOnly = 0
    case seconds30 = 30
    case minute1 = 60
    case minutes5 = 300
    case minutes10 = 600

    var id: Int { rawValue }
    var seconds: TimeInterval? { rawValue == 0 ? nil : TimeInterval(rawValue) }

    var label: String {
        switch self {
        case .networkChangesOnly: String(localized: "Network changes only")
        case .seconds30: String(localized: "Every 30 seconds")
        case .minute1: String(localized: "Every minute")
        case .minutes5: String(localized: "Every 5 minutes")
        case .minutes10: String(localized: "Every 10 minutes")
        }
    }
}

enum MenuBarDisplayMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case flag
    case flagAndCountry
    case countryCode
    case flagAndCode
    case flagAndCity
    case statusAndFlag
    case custom

    var id: String { rawValue }
    var label: String {
        switch self {
        case .flag: String(localized: "Flag")
        case .flagAndCountry: String(localized: "Flag and country")
        case .countryCode: String(localized: "Country code")
        case .flagAndCode: String(localized: "Flag and country code")
        case .flagAndCity: String(localized: "Flag and city")
        case .statusAndFlag: String(localized: "Status and flag")
        case .custom: String(localized: "Custom")
        }
    }
}

enum AppearanceMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AccentColorChoice: String, CaseIterable, Codable, Identifiable, Sendable {
    case prismBlue
    case oceanicTeal
    case sunsetOrange
    case emeraldGreen
    case auroraPurple
    case graphite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .prismBlue: String(localized: "Prism Blue")
        case .oceanicTeal: String(localized: "Oceanic Teal")
        case .sunsetOrange: String(localized: "Sunset Orange")
        case .emeraldGreen: String(localized: "Emerald Green")
        case .auroraPurple: String(localized: "Aurora Purple")
        case .graphite: String(localized: "Graphite")
        }
    }

    var color: Color {
        switch self {
        case .prismBlue:
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(red: 0.380, green: 0.620, blue: 0.965, alpha: 1.0)
                    : NSColor(red: 0.188, green: 0.482, blue: 0.933, alpha: 1.0)
            })
        case .oceanicTeal:
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(red: 0.18, green: 0.83, blue: 0.75, alpha: 1.0)
                    : NSColor(red: 0.05, green: 0.58, blue: 0.53, alpha: 1.0)
            })
        case .sunsetOrange:
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(red: 0.98, green: 0.57, blue: 0.24, alpha: 1.0)
                    : NSColor(red: 0.92, green: 0.35, blue: 0.05, alpha: 1.0)
            })
        case .emeraldGreen:
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(red: 0.29, green: 0.87, blue: 0.50, alpha: 1.0)
                    : NSColor(red: 0.09, green: 0.64, blue: 0.29, alpha: 1.0)
            })
        case .auroraPurple:
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(red: 0.65, green: 0.55, blue: 0.98, alpha: 1.0)
                    : NSColor(red: 0.49, green: 0.23, blue: 0.93, alpha: 1.0)
            })
        case .graphite:
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(red: 0.61, green: 0.64, blue: 0.69, alpha: 1.0)
                    : NSColor(red: 0.29, green: 0.33, blue: 0.39, alpha: 1.0)
            })
        }
    }
}

struct RefreshConfiguration: Equatable, Sendable {
    let interval: RefreshInterval
    let refreshOnNetworkChange: Bool
}
