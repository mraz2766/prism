import AppKit
import Foundation

@MainActor
final class RefreshCoordinator {
    private let lookupService: NetworkLookupService
    private let monitor: NetworkMonitor
    private let settings: SettingsStore
    private let realtimeExitMonitor: RealtimeExitMonitor
    private let domesticIPv4ViewModel: DomesticIPv4ViewModel
    private let proxyConfigurationMonitor: ProxyConfigurationMonitor

    private var timerTask: Task<Void, Never>?
    private var networkTask: Task<Void, Never>?
    private var settingsTask: Task<Void, Never>?
    private var realtimeControlTask: Task<Void, Never>?
    private var proxyConfigurationTask: Task<Void, Never>?
    private var environmentChangeTask: Task<Void, Never>?
    private var pendingSettingsTask: Task<Void, Never>?
    private var appliedConfiguration: RefreshConfiguration?
    private var observers: [NSObjectProtocol] = []
    private var isSleeping = false
    /// 一次 VPN/代理切换通常同时触发 NWPath 与 SCDynamicStore，合并为一次重新确认。
    private let environmentChangeDebounce: Duration = .milliseconds(200)
    /// 拖动灵敏度滑杆时只应用最终值。
    private let settingsDebounce: Duration = .milliseconds(300)

    init(
        lookupService: NetworkLookupService,
        monitor: NetworkMonitor,
        settings: SettingsStore,
        realtimeExitMonitor: RealtimeExitMonitor,
        domesticIPv4ViewModel: DomesticIPv4ViewModel,
        proxyConfigurationMonitor: ProxyConfigurationMonitor
    ) {
        self.lookupService = lookupService
        self.monitor = monitor
        self.settings = settings
        self.realtimeExitMonitor = realtimeExitMonitor
        self.domesticIPv4ViewModel = domesticIPv4ViewModel
        self.proxyConfigurationMonitor = proxyConfigurationMonitor
    }

    func start() {
        networkTask?.cancel()
        proxyConfigurationTask?.cancel()
        observeNetwork()
        observeProxyConfiguration()
        monitor.start()
        proxyConfigurationMonitor.start()
        appliedConfiguration = settings.refreshConfiguration
        observeSettings()
        observeSleepWake()
        restartTimer(configuration: settings.refreshConfiguration)
        domesticIPv4ViewModel.refresh()
        realtimeControlTask?.cancel()
        realtimeControlTask = Task { [realtimeExitMonitor] in
            guard !Task.isCancelled else { return }
            await realtimeExitMonitor.start()
        }
    }

    func stop() {
        timerTask?.cancel()
        networkTask?.cancel()
        proxyConfigurationTask?.cancel()
        settingsTask?.cancel()
        environmentChangeTask?.cancel()
        pendingSettingsTask?.cancel()
        realtimeControlTask?.cancel()
        realtimeControlTask = Task { [realtimeExitMonitor] in
            await realtimeExitMonitor.stop()
        }
        domesticIPv4ViewModel.stop()
        proxyConfigurationMonitor.stop()
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
        monitor.stop()
    }

    func triggerManual() {
        domesticIPv4ViewModel.refresh()
        Task {
            await realtimeExitMonitor.boost()
            await realtimeExitMonitor.refreshNow(showLoading: true)
        }
    }

    private func observeNetwork() {
        networkTask = Task { [weak self] in
            guard let self else { return }
            for await event in monitor.events() {
                switch event {
                case .offline:
                    environmentChangeTask?.cancel()
                    environmentChangeTask = nil
                    await realtimeExitMonitor.networkBecameUnavailable()
                    await lookupService.markOffline()
                    domesticIPv4ViewModel.markOffline()
                case .onlineChanged:
                    guard !isSleeping else { continue }
                    scheduleEnvironmentChange()
                }
            }
        }
    }

    private func observeProxyConfiguration() {
        proxyConfigurationTask = Task { [weak self] in
            guard let self else { return }
            for await _ in proxyConfigurationMonitor.events() {
                guard !isSleeping else { continue }
                scheduleEnvironmentChange()
            }
        }
    }

    private func scheduleEnvironmentChange() {
        environmentChangeTask?.cancel()
        let delay = environmentChangeDebounce
        environmentChangeTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, !Task.isCancelled, !isSleeping else { return }
            domesticIPv4ViewModel.refresh()
            await realtimeExitMonitor.networkEnvironmentDidChange()
        }
    }

    private func observeSettings() {
        settingsTask = Task { [weak self] in
            guard let self else { return }
            for await configuration in settings.changes() {
                pendingSettingsTask?.cancel()
                let delay = settingsDebounce
                pendingSettingsTask = Task { [weak self] in
                    do { try await Task.sleep(for: delay) } catch { return }
                    guard let self, !Task.isCancelled else { return }
                    await apply(configuration)
                }
            }
        }
    }

    private func apply(_ configuration: RefreshConfiguration) async {
        let previous = appliedConfiguration
        appliedConfiguration = configuration
        if previous?.detectionSensitivity != configuration.detectionSensitivity {
            await realtimeExitMonitor.updateSensitivity(configuration.detectionSensitivity)
        }
        if previous?.interval != configuration.interval {
            restartTimer(configuration: configuration)
        }
    }

    private func restartTimer(configuration: RefreshConfiguration) {
        timerTask?.cancel()
        guard let seconds = configuration.interval.seconds, !isSleeping else { return }
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(seconds)) } catch { break }
                guard let self, !isSleeping else { continue }
                domesticIPv4ViewModel.refresh()
                await realtimeExitMonitor.refreshNow()
            }
        }
    }

    private func observeSleepWake() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isSleeping = true
                self?.timerTask?.cancel()
                guard let self else { return }
                await self.realtimeExitMonitor.pause()
            }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                isSleeping = false
                restartTimer(configuration: settings.refreshConfiguration)
                try? await Task.sleep(for: .seconds(1.5))
                domesticIPv4ViewModel.refresh()
                await realtimeExitMonitor.resume()
                await realtimeExitMonitor.refreshNow()
            }
        })
    }
}
