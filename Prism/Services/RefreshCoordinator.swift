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

    private var networkTask: Task<Void, Never>?
    private var settingsTask: Task<Void, Never>?
    private var realtimeControlTask: Task<Void, Never>?
    private var proxyConfigurationTask: Task<Void, Never>?
    private var environmentChangeTask: Task<Void, Never>?
    private var pendingSettingsTask: Task<Void, Never>?
    private var appliedConfiguration: RefreshConfiguration?
    private var observers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    /// 系统睡眠、显示器休眠、锁屏、切换用户任一成立时暂停探测，全部解除后才恢复。
    private var pauseReasons: Set<PauseReason> = []
    private var resumeTask: Task<Void, Never>?
    private var isSleeping: Bool { !pauseReasons.isEmpty }
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
        settingsTask?.cancel()
        observeSettings()
        observeSleepWake()
        domesticIPv4ViewModel.refresh()
        realtimeControlTask?.cancel()
        let interval = Self.metadataInterval(settings.refreshConfiguration)
        realtimeControlTask = Task { [realtimeExitMonitor, domesticIPv4ViewModel] in
            guard !Task.isCancelled else { return }
            await realtimeExitMonitor.setPeriodicRefreshHandler { [weak domesticIPv4ViewModel] in
                await domesticIPv4ViewModel?.refresh()
            }
            await realtimeExitMonitor.updateMetadataRefreshInterval(interval)
            await realtimeExitMonitor.start()
        }
    }

    func stop() {
        networkTask?.cancel()
        proxyConfigurationTask?.cancel()
        settingsTask?.cancel()
        environmentChangeTask?.cancel()
        pendingSettingsTask?.cancel()
        resumeTask?.cancel()
        pauseReasons.removeAll()
        realtimeControlTask?.cancel()
        realtimeControlTask = Task { [realtimeExitMonitor] in
            await realtimeExitMonitor.stop()
        }
        domesticIPv4ViewModel.stop()
        proxyConfigurationMonitor.stop()
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
        let distributedCenter = DistributedNotificationCenter.default()
        distributedObservers.forEach(distributedCenter.removeObserver)
        distributedObservers.removeAll()
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
            await realtimeExitMonitor.updateMetadataRefreshInterval(Self.metadataInterval(configuration))
        }
    }

    private static func metadataInterval(_ configuration: RefreshConfiguration) -> Duration? {
        configuration.interval.seconds.map { .seconds($0) }
    }

    private enum PauseReason: Hashable {
        case systemSleep
        case displaySleep
        case screenLocked
        case sessionInactive
    }

    private func observeSleepWake() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
        let workspaceEvents: [(Notification.Name, PauseReason, Bool)] = [
            (NSWorkspace.willSleepNotification, .systemSleep, true),
            (NSWorkspace.didWakeNotification, .systemSleep, false),
            (NSWorkspace.screensDidSleepNotification, .displaySleep, true),
            (NSWorkspace.screensDidWakeNotification, .displaySleep, false),
            (NSWorkspace.sessionDidResignActiveNotification, .sessionInactive, true),
            (NSWorkspace.sessionDidBecomeActiveNotification, .sessionInactive, false)
        ]
        for (name, reason, isPausing) in workspaceEvents {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.update(reason, isPausing: isPausing) }
            })
        }

        // 锁屏没有公开的 NSWorkspace 通知，只能使用系统分布式通知。
        let distributedCenter = DistributedNotificationCenter.default()
        distributedObservers.forEach(distributedCenter.removeObserver)
        distributedObservers.removeAll()
        let lockEvents: [(String, Bool)] = [
            ("com.apple.screenIsLocked", true),
            ("com.apple.screenIsUnlocked", false)
        ]
        for (name, isPausing) in lockEvents {
            distributedObservers.append(distributedCenter.addObserver(
                forName: Notification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.update(.screenLocked, isPausing: isPausing) }
            })
        }
    }

    private func update(_ reason: PauseReason, isPausing: Bool) {
        let wasPaused = isSleeping
        if isPausing {
            pauseReasons.insert(reason)
        } else {
            pauseReasons.remove(reason)
        }

        if !wasPaused, isSleeping {
            resumeTask?.cancel()
            resumeTask = nil
            environmentChangeTask?.cancel()
            environmentChangeTask = nil
            Task { [realtimeExitMonitor] in await realtimeExitMonitor.pause() }
        } else if wasPaused, !isSleeping {
            // 刚从系统睡眠唤醒时网络尚未就绪，稍等再查询；其余情况立即补查。
            let delay: Duration = reason == .systemSleep ? .seconds(1.5) : .zero
            resumeTask?.cancel()
            resumeTask = Task { [weak self] in
                if delay > .zero {
                    do { try await Task.sleep(for: delay) } catch { return }
                }
                guard let self, !Task.isCancelled, !isSleeping else { return }
                domesticIPv4ViewModel.refresh()
                await realtimeExitMonitor.resume()
                await realtimeExitMonitor.refreshNow()
            }
        }
    }
}
