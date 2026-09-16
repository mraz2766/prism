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

enum DetectionSensitivity: Int, CaseIterable, Codable, Identifiable, Sendable {
    case energySaver
    case relaxed
    case balanced
    case responsive
    case maximum

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .energySaver: String(localized: "Energy Saver")
        case .relaxed: String(localized: "Relaxed")
        case .balanced: String(localized: "Balanced")
        case .responsive: String(localized: "Responsive")
        case .maximum: String(localized: "Maximum")
        }
    }

    var stableInterval: Duration {
        switch self {
        case .energySaver: .seconds(12)
        case .relaxed: .seconds(8)
        case .balanced: .seconds(5)
        case .responsive: .seconds(3)
        case .maximum: .seconds(2)
        }
    }

    var lowPowerInterval: Duration {
        switch self {
        case .energySaver: .seconds(30)
        case .relaxed: .seconds(20)
        case .balanced: .seconds(15)
        case .responsive: .seconds(8)
        case .maximum: .seconds(5)
        }
    }

    var confirmationInterval: Duration {
        switch self {
        case .energySaver: .milliseconds(500)
        case .relaxed: .milliseconds(350)
        case .balanced: .milliseconds(250)
        case .responsive: .milliseconds(150)
        case .maximum: .milliseconds(100)
        }
    }

    var unavailableFailureThreshold: Int {
        switch self {
        case .energySaver, .relaxed: 3
        case .balanced, .responsive: 2
        case .maximum: 1
        }
    }
}

enum MenuBarDisplayMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case flagAndCode
    case flagAndCity
    case countryCode
    case flagOnly
    case custom

    var id: String { rawValue }
    var label: String {
        switch self {
        case .flagAndCode: String(localized: "Flag and country code")
        case .flagAndCity: String(localized: "Flag and city")
        case .countryCode: String(localized: "Country code only")
        case .flagOnly: String(localized: "Flag only")
        case .custom: String(localized: "Custom")
        }
    }
}

enum CountryFlagStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case sticker
    case cartoon
    case waved
    case gradient
    case rounded
    case emoji

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sticker: String(localized: "Sticker flag")
        case .cartoon: String(localized: "Cartoon flag")
        case .waved: String(localized: "Waved flag")
        case .gradient: String(localized: "Gradient flag")
        case .rounded: String(localized: "Rounded flag")
        case .emoji: String(localized: "System Emoji")
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
        case .prismBlue: String(localized: "Spectrum Blue")
        case .oceanicTeal: String(localized: "Tidal Teal")
        case .sunsetOrange: String(localized: "Solar Orange")
        case .emeraldGreen: String(localized: "Tundra Green")
        case .auroraPurple: String(localized: "Aurora Purple")
        case .graphite: String(localized: "Graphite")
        }
    }

    var theme: AccentTheme {
        switch self {
        case .prismBlue:
            AccentTheme(
                light: RGBColor(red: 0.12, green: 0.42, blue: 0.88),
                dark: RGBColor(red: 0.37, green: 0.64, blue: 0.98)
            )
        case .oceanicTeal:
            AccentTheme(
                light: RGBColor(red: 0.03, green: 0.50, blue: 0.46),
                dark: RGBColor(red: 0.19, green: 0.78, blue: 0.72)
            )
        case .sunsetOrange:
            AccentTheme(
                light: RGBColor(red: 0.79, green: 0.31, blue: 0.05),
                dark: RGBColor(red: 1.00, green: 0.55, blue: 0.24)
            )
        case .emeraldGreen:
            AccentTheme(
                light: RGBColor(red: 0.07, green: 0.51, blue: 0.23),
                dark: RGBColor(red: 0.26, green: 0.85, blue: 0.47)
            )
        case .auroraPurple:
            AccentTheme(
                light: RGBColor(red: 0.44, green: 0.26, blue: 0.84),
                dark: RGBColor(red: 0.64, green: 0.51, blue: 1.00)
            )
        case .graphite:
            AccentTheme(
                light: RGBColor(red: 0.29, green: 0.33, blue: 0.39),
                dark: RGBColor(red: 0.67, green: 0.70, blue: 0.75)
            )
        }
    }

    var nsColor: NSColor {
        theme.nsColor
    }

    var color: Color {
        theme.primary
    }
}

struct AccentTheme: Sendable {
    let light: RGBColor
    let dark: RGBColor

    var nsColor: NSColor {
        NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return value.nsColor
        }
    }

    var primary: Color { Color(nsColor: nsColor) }
    var pressed: Color { primary.opacity(0.82) }
    var softBackground: Color { primary.opacity(0.12) }

    func foreground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.black.opacity(0.86) : .white
    }
}

struct RGBColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    var nsColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: 1)
    }
}

struct RefreshConfiguration: Equatable, Sendable {
    let interval: RefreshInterval
    let refreshOnNetworkChange: Bool
    let detectionSensitivity: DetectionSensitivity

    init(
        interval: RefreshInterval,
        refreshOnNetworkChange: Bool,
        detectionSensitivity: DetectionSensitivity = .responsive
    ) {
        self.interval = interval
        self.refreshOnNetworkChange = refreshOnNetworkChange
        self.detectionSensitivity = detectionSensitivity
    }
}
