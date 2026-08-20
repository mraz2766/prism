import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class DashboardNavigationModel {
    enum Destination: String, CaseIterable, Identifiable {
        case overview
        case history
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
    let settingsViewModel: SettingsViewModel
    let refreshCoordinator: RefreshCoordinator
    let notificationService: NotificationService
    let providerHealth: ProviderHealthRegistry
    let dashboardNavigation = DashboardNavigationModel()

    var openSettingsAction: (@MainActor () -> Void)?
    var dashboardWindowController: DashboardWindowController?

    @ObservationIgnored private var notificationTask: Task<Void, Never>?
    @ObservationIgnored private var started = false

    init(isUITesting: Bool = ProcessInfo.processInfo.arguments.contains("--ui-testing")) {
        settings = SettingsStore(defaults: isUITesting ? Self.makeUITestDefaults() : .standard)
        if isUITesting {
            historyStore = NetworkHistoryStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("prism-ui-tests-\(UUID().uuidString).json"),
                settlingDelay: .zero,
                initialEntries: [NetworkHistoryEntry(info: .preview)]
            )
        } else {
            historyStore = NetworkHistoryStore()
        }
        let cache = NetworkInfoCache()
        providerHealth = ProviderHealthRegistry()
        let publicIP: any PublicIPProviding = isUITesting
            ? PreviewPublicIPProvider()
            : PublicIPService()
        let geo: any GeoIPProvider = isUITesting
            ? PreviewGeoIPProvider()
            : FallbackGeoIPProvider(providers: [
                IPWhoIsGeoProvider(),
                IPGuideGeoProvider(),
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
            history: historyStore
        )
        networkViewModel = NetworkStatusViewModel(service: lookupService)
        let launchService = LaunchAtLoginService()
        notificationService = NotificationService()
        settingsViewModel = SettingsViewModel(
            settings: settings,
            launchAtLoginService: launchService,
            notificationService: notificationService
        )
        let exitProbe: any ExitAddressProbing = isUITesting
            ? PreviewExitAddressProbe()
            : IPifyExitAddressProbe()
        let realtimeExitMonitor = RealtimeExitMonitor(
            probe: exitProbe,
            lookupService: lookupService
        )
        refreshCoordinator = RefreshCoordinator(
            lookupService: lookupService,
            monitor: NetworkMonitor(),
            settings: settings,
            realtimeExitMonitor: realtimeExitMonitor
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
        networkViewModel.start()
        observeForNotifications()
        refreshCoordinator.start()
    }

    func stop() {
        notificationTask?.cancel()
        refreshCoordinator.stop()
        started = false
    }

    func showDashboard(_ destination: DashboardNavigationModel.Destination = .overview) {
        dashboardNavigation.destination = destination
        dashboardWindowController?.showWindow()
    }

    private func observeForNotifications() {
        notificationTask = Task { [weak self, lookupService] in
            var previous: NetworkInfo?
            for await status in lookupService.stream() {
                guard let self, case .online(let current) = status else { continue }
                defer { previous = current }
                guard let old = previous,
                      old.id != current.id,
                      settings.changeNotificationsEnabled else { continue }
                await notificationService.notifyExitChange(from: old, to: current)
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
    func lookup(ipAddress: String) async throws -> GeoIPResult {
        GeoIPResult(
            location: NetworkInfo.preview.location,
            network: NetworkInfo.preview.network,
            providerIdentifier: identifier
        )
    }
}

private struct PreviewPrivacyProvider: PrivacyClassifying {
    func classify(ipAddress: String) async throws -> PrivacyClassification { .suspected }
}

private struct PreviewExitAddressProbe: ExitAddressProbing {
    func observeExit() async throws -> ExitObservation {
        ExitObservation(
            addresses: NetworkInfo.preview.addresses,
            source: .overseasIPv4,
            routeMode: .proxy
        )
    }
}
