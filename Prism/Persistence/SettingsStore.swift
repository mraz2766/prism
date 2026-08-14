import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    var refreshInterval: RefreshInterval { didSet { persist(); emit() } }
    var refreshOnNetworkChange: Bool { didSet { persist(); emit() } }
    var changeNotificationsEnabled: Bool { didSet { persist(); emit() } }
    var launchAtLogin: Bool { didSet { persist(); emit() } }
    var menuBarDisplayMode: MenuBarDisplayMode { didSet { persist(); emit() } }
    var customMenuTemplate: String { didSet { persist(); emit() } }
    var appearanceMode: AppearanceMode { didSet { persist(); emit() } }

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
        menuBarDisplayMode = defaults.string(forKey: Keys.displayMode)
            .flatMap(MenuBarDisplayMode.init(rawValue:)) ?? .flagAndCountry
        customMenuTemplate = defaults.string(forKey: Keys.customTemplate) ?? "{flag} {country}"
        appearanceMode = defaults.string(forKey: Keys.appearance)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .system
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

    private func persist() {
        defaults.set(refreshInterval.rawValue, forKey: Keys.refreshInterval)
        defaults.set(refreshOnNetworkChange, forKey: Keys.refreshOnNetworkChange)
        defaults.set(changeNotificationsEnabled, forKey: Keys.changeNotifications)
        defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
        defaults.set(menuBarDisplayMode.rawValue, forKey: Keys.displayMode)
        defaults.set(customMenuTemplate, forKey: Keys.customTemplate)
        defaults.set(appearanceMode.rawValue, forKey: Keys.appearance)
    }

    private func emit() {
        let configuration = refreshConfiguration
        continuations.values.forEach { $0.yield(configuration) }
    }

    private enum Keys {
        static let refreshInterval = "refresh.interval"
        static let refreshOnNetworkChange = "refresh.onNetworkChange"
        static let changeNotifications = "notifications.exitChanges"
        static let launchAtLogin = "launchAtLogin"
        static let displayMode = "menuBar.displayMode"
        static let customTemplate = "menuBar.customTemplate"
        static let appearance = "appearance.mode"
    }
}
