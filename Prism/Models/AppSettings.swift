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

struct RefreshConfiguration: Equatable, Sendable {
    let interval: RefreshInterval
    let refreshOnNetworkChange: Bool
}
