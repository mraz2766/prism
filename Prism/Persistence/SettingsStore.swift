import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    var refreshInterval: RefreshInterval {
        didSet {
            guard oldValue != refreshInterval else { return }
            defaults.set(refreshInterval.rawValue, forKey: Keys.refreshInterval)
            emit()
        }
    }
    var refreshOnNetworkChange: Bool {
        didSet {
            guard oldValue != refreshOnNetworkChange else { return }
            defaults.set(refreshOnNetworkChange, forKey: Keys.refreshOnNetworkChange)
            emit()
        }
    }
    var detectionSensitivity: DetectionSensitivity {
        didSet {
            guard oldValue != detectionSensitivity else { return }
            defaults.set(detectionSensitivity.rawValue, forKey: Keys.detectionSensitivity)
            emit()
        }
    }
    var changeNotificationsEnabled: Bool {
        didSet {
            guard oldValue != changeNotificationsEnabled else { return }
            defaults.set(changeNotificationsEnabled, forKey: Keys.changeNotifications)
        }
    }
    var launchAtLogin: Bool {
        didSet {
            guard oldValue != launchAtLogin else { return }
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
        }
    }
    var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            guard oldValue != menuBarDisplayMode else { return }
            defaults.set(menuBarDisplayMode.rawValue, forKey: Keys.displayMode)
        }
    }
    var countryFlagStyle: CountryFlagStyle {
        didSet {
            guard oldValue != countryFlagStyle else { return }
            defaults.set(countryFlagStyle.rawValue, forKey: Keys.flagStyle)
        }
    }
    var customMenuTemplate: String {
        didSet {
            guard oldValue != customMenuTemplate else { return }
            defaults.set(customMenuTemplate, forKey: Keys.customTemplate)
        }
    }
    var appearanceMode: AppearanceMode {
        didSet {
            guard oldValue != appearanceMode else { return }
            defaults.set(appearanceMode.rawValue, forKey: Keys.appearance)
        }
    }
    var accentColorChoice: AccentColorChoice {
        didSet {
            guard oldValue != accentColorChoice else { return }
            defaults.set(accentColorChoice.rawValue, forKey: Keys.accentColor)
        }
    }

    var regionGuardEnabled: Bool {
        didSet {
            guard oldValue != regionGuardEnabled else { return }
            defaults.set(regionGuardEnabled, forKey: Keys.regionGuardEnabled)
        }
    }
    /// 用户输入的期望地区，逗号或空格分隔的 ISO 国家代码，例如 "JP, US"。
    var regionGuardCountries: String {
        didSet {
            guard oldValue != regionGuardCountries else { return }
            defaults.set(regionGuardCountries, forKey: Keys.regionGuardCountries)
        }
    }
    var globalHotKey: GlobalHotKeyChoice {
        didSet {
            guard oldValue != globalHotKey else { return }
            defaults.set(globalHotKey.rawValue, forKey: Keys.globalHotKey)
        }
    }

    var regionGuard: RegionGuard {
        RegionGuard(isEnabled: regionGuardEnabled, expectedCountries: regionGuardCountries)
    }

    var automaticRefreshEnabled: Bool {
        get { refreshInterval != .networkChangesOnly }
        set {
            if newValue {
                if refreshInterval == .networkChangesOnly { refreshInterval = .minute1 }
            } else {
                refreshOnNetworkChange = true
                refreshInterval = .networkChangesOnly
            }
        }
    }

    var refreshConfiguration: RefreshConfiguration {
        RefreshConfiguration(
            interval: refreshInterval,
            refreshOnNetworkChange: refreshInterval == .networkChangesOnly ? true : refreshOnNetworkChange,
            detectionSensitivity: detectionSensitivity
        )
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var continuations: [UUID: AsyncStream<RefreshConfiguration>.Continuation] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Keys.refreshInterval) == nil {
            refreshInterval = .minute1
        } else {
            refreshInterval = RefreshInterval(rawValue: defaults.integer(forKey: Keys.refreshInterval)) ?? .minute1
        }
        refreshOnNetworkChange = defaults.object(forKey: Keys.refreshOnNetworkChange) as? Bool ?? true
        if defaults.object(forKey: Keys.detectionSensitivity) == nil {
            detectionSensitivity = .responsive
        } else {
            detectionSensitivity = DetectionSensitivity(
                rawValue: defaults.integer(forKey: Keys.detectionSensitivity)
            ) ?? .responsive
        }
        changeNotificationsEnabled = defaults.bool(forKey: Keys.changeNotifications)
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        menuBarDisplayMode = Self.migratedDisplayMode(defaults.string(forKey: Keys.displayMode))
        countryFlagStyle = Self.migratedFlagStyle(defaults.string(forKey: Keys.flagStyle))
        customMenuTemplate = defaults.string(forKey: Keys.customTemplate) ?? "{flag} {code}"
        appearanceMode = defaults.string(forKey: Keys.appearance)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .system
        accentColorChoice = defaults.string(forKey: Keys.accentColor)
            .flatMap(AccentColorChoice.init(rawValue:)) ?? .prismBlue
        regionGuardEnabled = defaults.bool(forKey: Keys.regionGuardEnabled)
        regionGuardCountries = defaults.string(forKey: Keys.regionGuardCountries) ?? ""
        globalHotKey = defaults.string(forKey: Keys.globalHotKey)
            .flatMap(GlobalHotKeyChoice.init(rawValue:)) ?? .off
    }

    func changes() -> AsyncStream<RefreshConfiguration> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.yield(refreshConfiguration)
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor [weak self] in self?.continuations.removeValue(forKey: id) }
            }
        }
    }

    private func emit() {
        let configuration = refreshConfiguration
        continuations.values.forEach { $0.yield(configuration) }
    }

    private static func migratedDisplayMode(_ rawValue: String?) -> MenuBarDisplayMode {
        if let rawValue, let current = MenuBarDisplayMode(rawValue: rawValue) { return current }
        return switch rawValue {
        case "routeAndCode": .flagAndCity
        case "iconOnly", "flag": .flagOnly
        case "flagAndCountry", "statusAndFlag": .flagAndCode
        default: .flagAndCode
        }
    }

    private static func migratedFlagStyle(_ rawValue: String?) -> CountryFlagStyle {
        if let rawValue, let current = CountryFlagStyle(rawValue: rawValue) { return current }
        return switch rawValue {
        case "flat", "badge", "circle", "sticker", "rounded": .gradient
        default: .gradient
        }
    }

    private enum Keys {
        static let refreshInterval = "refresh.interval"
        static let refreshOnNetworkChange = "refresh.onNetworkChange"
        static let detectionSensitivity = "detection.sensitivity"
        static let changeNotifications = "notifications.exitChanges"
        static let launchAtLogin = "launchAtLogin"
        static let displayMode = "menuBar.displayMode"
        static let flagStyle = "menuBar.flagStyle"
        static let customTemplate = "menuBar.customTemplate"
        static let appearance = "appearance.mode"
        static let accentColor = "appearance.accentColor"
        static let regionGuardEnabled = "regionGuard.enabled"
        static let regionGuardCountries = "regionGuard.countries"
        static let globalHotKey = "hotKey.togglePopover"
    }
}
