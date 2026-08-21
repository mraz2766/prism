import AppKit
import Foundation

@MainActor
final class RefreshCoordinator {
    private let lookupService: NetworkLookupService
    private let monitor: NetworkMonitor
    private let settings: SettingsStore
    private let realtimeExitMonitor: RealtimeExitMonitor
    private let domesticIPv4ViewModel: DomesticIPv4ViewModel

    private var timerTask: Task<Void, Never>?
    private var networkTask: Task<Void, Never>?
    private var settingsTask: Task<Void, Never>?
    private var realtimeControlTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var isSleeping = false

    init(
        lookupService: NetworkLookupService,
        monitor: NetworkMonitor,
        settings: SettingsStore,
        realtimeExitMonitor: RealtimeExitMonitor,
        domesticIPv4ViewModel: DomesticIPv4ViewModel
    ) {
        self.lookupService = lookupService
        self.monitor = monitor
        self.settings = settings
        self.realtimeExitMonitor = realtimeExitMonitor
        self.domesticIPv4ViewModel = domesticIPv4ViewModel
    }

    func start() {
        monitor.start()
        observeNetwork()
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
        settingsTask?.cancel()
        realtimeControlTask?.cancel()
        realtimeControlTask = Task { [realtimeExitMonitor] in
            await realtimeExitMonitor.stop()
        }
        domesticIPv4ViewModel.stop()
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
                    await lookupService.markOffline()
                    domesticIPv4ViewModel.markOffline()
                case .onlineChanged:
                    guard settings.refreshConfiguration.refreshOnNetworkChange, !isSleeping else { continue }
                    domesticIPv4ViewModel.refresh()
                    await realtimeExitMonitor.boost()
                    await realtimeExitMonitor.refreshNow()
                }
            }
        }
    }

    private func observeSettings() {
        settingsTask = Task { [weak self] in
            guard let self else { return }
            for await configuration in settings.changes() {
                restartTimer(configuration: configuration)
            }
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
