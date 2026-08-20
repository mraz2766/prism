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
            refreshOnNetworkChange: refreshInterval == .networkChangesOnly ? true : refreshOnNetworkChange
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
        changeNotificationsEnabled = defaults.bool(forKey: Keys.changeNotifications)
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        menuBarDisplayMode = Self.migratedDisplayMode(defaults.string(forKey: Keys.displayMode))
        countryFlagStyle = Self.migratedFlagStyle(defaults.string(forKey: Keys.flagStyle))
        customMenuTemplate = defaults.string(forKey: Keys.customTemplate) ?? "{flag} {code}"
        appearanceMode = defaults.string(forKey: Keys.appearance)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .system
        accentColorChoice = defaults.string(forKey: Keys.accentColor)
            .flatMap(AccentColorChoice.init(rawValue:)) ?? .prismBlue
    }

    func changes() -> AsyncStream<RefreshConfiguration> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.yield(refreshConfiguration)
            continuation.onTermination = { @Sendable _ in
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
        case "flag", "flagAndCountry", "flagAndCity", "statusAndFlag": .flagAndCode
        default: .flagAndCode
        }
    }

    private static func migratedFlagStyle(_ rawValue: String?) -> CountryFlagStyle {
        if let rawValue, let current = CountryFlagStyle(rawValue: rawValue) { return current }
        return switch rawValue {
        case "flat", "badge", "circle": .sticker
        default: .sticker
        }
    }

    private enum Keys {
        static let refreshInterval = "refresh.interval"
        static let refreshOnNetworkChange = "refresh.onNetworkChange"
        static let changeNotifications = "notifications.exitChanges"
        static let launchAtLogin = "launchAtLogin"
        static let displayMode = "menuBar.displayMode"
        static let flagStyle = "menuBar.flagStyle"
        static let customTemplate = "menuBar.customTemplate"
        static let appearance = "appearance.mode"
        static let accentColor = "appearance.accentColor"
    }
}
