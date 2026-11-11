import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class DashboardNavigationModel {
    enum Destination: String, CaseIterable, Identifiable {
        case overview
        case history
        case diagnostics
        var id: String { rawValue }
    }

    var destination: Destination = .overview
}

@MainActor
@Observable
final class AppEnvironment {
    let settings: SettingsStore
    let historyStore: NetworkHistoryStore
    let lookupService: NetworkLookupService
    let networkViewModel: NetworkStatusViewModel
    let domesticIPv4ViewModel: DomesticIPv4ViewModel
    let settingsViewModel: SettingsViewModel
    let refreshCoordinator: RefreshCoordinator
    let notificationService: NotificationService
    let providerHealth: ProviderHealthRegistry
    let cityLocalizer: CityLocalizer
    let latencyModel = ProbeLatencyModel()
    let dashboardNavigation = DashboardNavigationModel()
    /// 所选全局快捷键已被系统或其他应用占用。
    private(set) var hotKeyUnavailable = false

    /// 当前已确认的出口是否落在期望地区之外。
    var isOutsideExpectedRegion: Bool {
        settings.regionGuard.isViolated(by: networkViewModel.status)
    }

    var openSettingsAction: (@MainActor () -> Void)?
    var dashboardWindowController: DashboardWindowController?
    @ObservationIgnored private weak var settingsWindow: NSWindow?

    @ObservationIgnored private var notificationTask: Task<Void, Never>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private let globalHotKey = GlobalHotKey()
    @ObservationIgnored private var lastGuardAlertCountry: String?

    init(isUITesting: Bool = ProcessInfo.processInfo.arguments.contains("--ui-testing")) {
        let testLocationFailure = isUITesting && (
            ProcessInfo.processInfo.arguments.contains("--ui-testing-location-unavailable") ||
            ProcessInfo.processInfo.arguments.contains("--ui-testing-offline-country")
        )
        let uiTestDirectory = isUITesting
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent("prism-ui-tests-\(UUID().uuidString)", isDirectory: true)
            : nil
        let defaults: UserDefaults = isUITesting ? Self.makeUITestDefaults() : .standard
        settings = SettingsStore(defaults: defaults)
        cityLocalizer = isUITesting
            ? CityLocalizer(defaults: defaults, lookup: nil)
            : CityLocalizer(defaults: defaults)
        if isUITesting {
            historyStore = NetworkHistoryStore(
                fileURL: uiTestDirectory!.appendingPathComponent("history.json"),
                settlingDelay: .zero,
                initialEntries: testLocationFailure ? [] : [NetworkHistoryEntry(info: .preview)]
            )
        } else {
            historyStore = NetworkHistoryStore()
        }
        let cache = NetworkInfoCache(directory: uiTestDirectory)
        providerHealth = ProviderHealthRegistry()
        let publicIP: any PublicIPProviding = isUITesting
            ? PreviewPublicIPProvider()
            : PublicIPService()
        let geo: any GeoIPProvider = isUITesting
            ? PreviewGeoIPProvider(
                failsLookup: testLocationFailure
            )
            : FallbackGeoIPProvider(providers: [
                IPWhoIsGeoProvider(),
                IPGuideGeoProvider(),
                IPSBGeoProvider(),
                IPIPGeoProvider()
            ], health: providerHealth)
        let privacy: any PrivacyClassifying = isUITesting
            ? PreviewPrivacyProvider()
            : PrivacyClassificationService()
        lookupService = NetworkLookupService(
            publicIPProvider: publicIP,
            geoProvider: geo,
            privacyProvider: privacy,
            cache: cache,
            history: historyStore,
            countryLookup: isUITesting
                ? PreviewCountryLookup(country: ProcessInfo.processInfo.arguments.contains("--ui-testing-offline-country") ? "JP" : nil)
                : OfflineCountryLookup()
        )
        networkViewModel = NetworkStatusViewModel(service: lookupService)
        let domesticProbe: any DomesticIPv4Probing = isUITesting
            ? PreviewDomesticIPv4Probe()
            : IPIPDomesticIPv4Probe()
        domesticIPv4ViewModel = DomesticIPv4ViewModel(probe: domesticProbe)
        let launchService = LaunchAtLoginService()
        notificationService = NotificationService()
        settingsViewModel = SettingsViewModel(
            settings: settings,
            launchAtLoginService: launchService,
            notificationService: notificationService
        )
        let exitProbe: any ExitAddressProbing = isUITesting
            ? PreviewExitAddressProbe(isDomesticFallback: ProcessInfo.processInfo.arguments.contains("--ui-testing-domestic-fallback"))
            : IPifyExitAddressProbe(latencyRecorder: { [latencyModel] duration in
                Task { @MainActor in latencyModel.record(duration) }
            })
        let realtimeExitMonitor = RealtimeExitMonitor(
            probe: exitProbe,
            lookupService: lookupService,
            sensitivity: settings.detectionSensitivity
        )
        let proxyConfigurationMonitor = ProxyConfigurationMonitor()
        refreshCoordinator = RefreshCoordinator(
            lookupService: lookupService,
            monitor: NetworkMonitor(),
            settings: settings,
            realtimeExitMonitor: realtimeExitMonitor,
            domesticIPv4ViewModel: domesticIPv4ViewModel,
            proxyConfigurationMonitor: proxyConfigurationMonitor
        )
    }

    private static func makeUITestDefaults() -> UserDefaults {
        let suiteName = "com.mraz.prism.ui-tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return .standard }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func start() {
        guard !started else { return }
        started = true
        observeAppearance()
        observeHotKey()
        notificationService.install()
        notificationService.onOpenHistory = { [weak self] in self?.showDashboard(.history) }
        networkViewModel.start()
        observeForNotifications()
        refreshCoordinator.start()
    }

    func stop() {
        notificationTask?.cancel()
        globalHotKey.unregister()
        refreshCoordinator.stop()
        started = false
    }

    /// 打开设置窗口。菜单栏 accessory 应用必须先激活，否则 SwiftUI Settings 窗口不会出现在前台。
    func openSettings() {
        NSApp.activate()
        if let settingsWindow, settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
        } else if let openSettingsAction {
            // 新建的窗口由 SettingsRootView 挂载后通过 registerSettingsWindow 置前。
            openSettingsAction()
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    func registerSettingsWindow(_ window: NSWindow) {
        settingsWindow = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func showDashboard(_ destination: DashboardNavigationModel.Destination = .overview) {
        dashboardNavigation.destination = destination
        dashboardWindowController?.showWindow()
    }

    private func observeForNotifications() {
        notificationTask = Task { [weak self, lookupService] in
            var previous: NetworkInfo?
            for await status in lookupService.stream() {
                guard let self else { return }
                cityLocalizer.resolveIfNeeded(for: status)
                if status.isOffline { latencyModel.reset() }
                guard case .online(let current) = status else { continue }
                let old = previous
                previous = current
                if let old, old.id != current.id {
                    domesticIPv4ViewModel.refreshIfStale()
                    if settings.changeNotificationsEnabled {
                        await notificationService.notify(
                            Self.changeEvent(from: old, to: current),
                            cityName: { [cityLocalizer] in cityLocalizer.displayCity(for: $0) }
                        )
                    }
                }
                await alertRegionGuardIfNeeded(for: current)
            }
        }
    }

    static func changeEvent(from old: NetworkInfo, to current: NetworkInfo) -> ExitNotificationEvent {
        let wasDomestic = old.exitSource == .domesticFallback
        let isDomestic = current.exitSource == .domesticFallback
        if !wasDomestic && isDomestic { return .fellBackToDomestic(current) }
        if wasDomestic && !isDomestic { return .overseasRecovered(current) }
        return .exitChanged(from: old, to: current)
    }

    /// 同一个越界国家只提醒一次；回到期望地区后重新布防。
    private func alertRegionGuardIfNeeded(for current: NetworkInfo) async {
        let guardRule = settings.regionGuard
        let code = current.location.countryCode.uppercased()
        guard guardRule.isViolated(by: code) else {
            if guardRule.isActive, !code.isEmpty { lastGuardAlertCountry = nil }
            return
        }
        guard lastGuardAlertCountry != code else { return }
        lastGuardAlertCountry = code
        await notificationService.notify(
            .leftExpectedRegion(current, expected: guardRule.expectedCodes),
            cityName: { [cityLocalizer] in cityLocalizer.displayCity(for: $0) }
        )
    }

    private func observeHotKey() {
        hotKeyUnavailable = !globalHotKey.apply(settings.globalHotKey)
        withObservationTracking {
            _ = settings.globalHotKey
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.started else { return }
                self.observeHotKey()
            }
        }
    }

    private func observeAppearance() {
        applyAppearance()
        withObservationTracking {
            _ = settings.appearanceMode
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.started else { return }
                self.observeAppearance()
            }
        }
    }

    private func applyAppearance() {
        NSApp.appearance = switch settings.appearanceMode {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

private struct PreviewPublicIPProvider: PublicIPProviding {
    func fetchAddresses() async throws -> IPAddressSet { NetworkInfo.preview.addresses }
}

private struct PreviewGeoIPProvider: GeoIPProvider {
    let identifier = "preview"
    var failsLookup = false

    func lookup(ipAddress: String) async throws -> GeoIPResult {
        if failsLookup { throw NetworkFailure.timeout }
        return GeoIPResult(
            location: NetworkInfo.preview.location,
            network: NetworkInfo.preview.network,
            providerIdentifier: identifier
        )
    }
}

private struct PreviewPrivacyProvider: PrivacyClassifying {
    func classify(ipAddress: String) async throws -> PrivacyClassification { .suspected }
}

private struct PreviewDomesticIPv4Probe: DomesticIPv4Probing {
    func fetch() async throws -> DomesticIPv4Info {
        DomesticIPv4Info(
            address: "198.51.100.86",
            isChinese: true,
            checkedAt: .now
        )
    }
}

private struct PreviewExitAddressProbe: ExitAddressProbing {
    var isDomesticFallback = false

    func observeExit() async throws -> ExitObservation {
        ExitObservation(
            addresses: isDomesticFallback ? IPAddressSet(ipv4: "198.51.100.86", ipv6: nil) : NetworkInfo.preview.addresses,
            source: isDomesticFallback ? .domesticFallback : .overseasIPv4,
            routeMode: isDomesticFallback ? .unknown : .proxy,
            preResolvedGeo: isDomesticFallback ? GeoIPResult(
                location: NetworkInfo.preview.location,
                network: NetworkInfo.preview.network,
                providerIdentifier: "preview-domestic"
            ) : nil
        )
    }
}

private struct PreviewCountryLookup: CountryLookingUp {
    let country: String?
    func countryCode(for ipAddress: String) -> String? { country }
}
