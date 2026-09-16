import Foundation
import OSLog

actor RealtimeExitMonitor {
    private let probe: any ExitAddressProbing
    private let lookupService: NetworkLookupService
    private var stableInterval: Duration
    private var lowPowerInterval: Duration
    private var burstInterval: Duration
    private var burstDuration: Duration
    private var unavailableFailureThreshold: Int
    private let isLowPowerModeEnabled: @Sendable () -> Bool
    private let clock = ContinuousClock()
    private let logger = Logger(subsystem: "com.mraz.prism", category: "realtime-exit")

    private var loopTask: Task<Void, Never>?
    private var observationTask: Task<Void, Never>?
    private var activeRefreshesUnchanged = false
    private var queuedRefreshesUnchanged = false
    private var queuedShowLoading = false
    private var isPaused = false
    private var burstUntil: ContinuousClock.Instant?
    private var stabilizer = ExitStabilizer()
    private var observationGeneration = 0
    private var consecutiveFailures = 0
    private var probeWasUnavailable = false

    init(
        probe: any ExitAddressProbing,
        lookupService: NetworkLookupService,
        sensitivity: DetectionSensitivity = .responsive,
        isLowPowerModeEnabled: @escaping @Sendable () -> Bool = {
            ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    ) {
        self.probe = probe
        self.lookupService = lookupService
        stableInterval = sensitivity.stableInterval
        lowPowerInterval = sensitivity.lowPowerInterval
        burstInterval = sensitivity.confirmationInterval
        burstDuration = .seconds(2)
        unavailableFailureThreshold = sensitivity.unavailableFailureThreshold
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
    }

    init(
        probe: any ExitAddressProbing,
        lookupService: NetworkLookupService,
        interval: Duration,
        lowPowerInterval: Duration = .seconds(15),
        retryBackoff: Duration = .seconds(5),
        burstInterval: Duration = .milliseconds(250),
        burstDuration: Duration = .seconds(2),
        unavailableFailureThreshold: Int = 2,
        isLowPowerModeEnabled: @escaping @Sendable () -> Bool = {
            ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    ) {
        self.probe = probe
        self.lookupService = lookupService
        self.stableInterval = interval
        self.lowPowerInterval = lowPowerInterval
        self.burstInterval = burstInterval
        self.burstDuration = burstDuration
        self.unavailableFailureThreshold = max(1, unavailableFailureThreshold)
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        _ = retryBackoff
    }

    func start() {
        guard loopTask == nil else { return }
        isPaused = false
        boost()
        loopTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        loopTask?.cancel()
        observationTask?.cancel()
        loopTask = nil
        observationTask = nil
        activeRefreshesUnchanged = false
        queuedRefreshesUnchanged = false
        queuedShowLoading = false
        burstUntil = nil
        observationGeneration &+= 1
        consecutiveFailures = 0
        probeWasUnavailable = false
        stabilizer.reset()
    }

    func pause() {
        isPaused = true
    }

    func resume() {
        isPaused = false
        boost()
    }

    func boost() {
        burstUntil = clock.now.advanced(by: burstDuration)
    }

    func updateSensitivity(_ sensitivity: DetectionSensitivity) {
        stableInterval = sensitivity.stableInterval
        lowPowerInterval = sensitivity.lowPowerInterval
        burstInterval = sensitivity.confirmationInterval
        unavailableFailureThreshold = sensitivity.unavailableFailureThreshold
        consecutiveFailures = 0
        probeWasUnavailable = false
        boost()

        guard loopTask != nil else { return }
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func pollNow() async {
        await observeAndApply(refreshUnchanged: false, showLoading: false)
    }

    func refreshNow(showLoading: Bool = false) async {
        await observeAndApply(refreshUnchanged: true, showLoading: showLoading)
    }

    func networkEnvironmentDidChange(showLoading: Bool = false) async {
        guard !isPaused, !Task.isCancelled else { return }
        observationGeneration &+= 1
        consecutiveFailures = 0
        probeWasUnavailable = false
        stabilizer.reset()
        boost()
        await lookupService.cancelRefreshForEnvironmentChange()
        await probe.invalidateConnections()
        await observeAndApply(
            refreshUnchanged: true,
            showLoading: showLoading,
            forceNewObservation: true
        )
    }

    func networkBecameUnavailable() async {
        observationGeneration &+= 1
        consecutiveFailures = 0
        probeWasUnavailable = false
        stabilizer.reset()
        await lookupService.cancelRefreshForEnvironmentChange()
        await probe.invalidateConnections()
    }

    private func observeAndApply(
        refreshUnchanged: Bool,
        showLoading: Bool,
        forceNewObservation: Bool = false
    ) async {
        guard !isPaused, !Task.isCancelled else { return }

        if let observationTask {
            if forceNewObservation || (refreshUnchanged && !activeRefreshesUnchanged) {
                queuedRefreshesUnchanged = true
                queuedShowLoading = queuedShowLoading || showLoading
            }
            await observationTask.value
            return
        }

        activeRefreshesUnchanged = refreshUnchanged
        let generation = observationGeneration
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.performObservation(
                refreshUnchanged: refreshUnchanged,
                showLoading: showLoading,
                generation: generation
            )
        }
        observationTask = task
        await task.value
        observationTask = nil
        activeRefreshesUnchanged = false

        if queuedRefreshesUnchanged, !Task.isCancelled {
            let shouldShowLoading = queuedShowLoading
            queuedRefreshesUnchanged = false
            queuedShowLoading = false
            await observeAndApply(refreshUnchanged: true, showLoading: shouldShowLoading)
        }
    }

    private func performObservation(
        refreshUnchanged: Bool,
        showLoading: Bool,
        generation: Int
    ) async {
        guard !isPaused, !Task.isCancelled else { return }

        do {
            let observation = try await probe.observeExit()
            guard generation == observationGeneration, !isPaused else { return }
            consecutiveFailures = 0
            let restoresProbeAvailability = probeWasUnavailable
            probeWasUnavailable = false
            let currentInfo = await lookupService.comparisonInfo()
            let needsRecoveryRefresh = await lookupService.snapshot().needsRecoveryRefresh
            guard generation == observationGeneration, !isPaused else { return }
            switch stabilizer.evaluate(observation, currentInfo: currentInfo) {
            case .unchanged:
                if restoresProbeAvailability,
                   await lookupService.restoreProbeAvailability(observation) { return }
                if refreshUnchanged || needsRecoveryRefresh {
                    _ = await lookupService.refresh(observation: observation, showLoading: showLoading)
                }
            case .cancelled:
                await lookupService.cancelVerification()
                if restoresProbeAvailability,
                   await lookupService.restoreProbeAvailability(observation) { return }
                if refreshUnchanged || needsRecoveryRefresh {
                    _ = await lookupService.refresh(observation: observation, showLoading: showLoading)
                }
            case .pending(let candidate):
                boost()
                await lookupService.markVerifying(candidate)
            case .confirmed(let confirmed):
                boost()
                logger.info("Confirmed a changed public exit address")
                _ = await lookupService.refresh(observation: confirmed)
            }
            return
        } catch {
            guard generation == observationGeneration else { return }
            let failure = NetworkFailure.map(error)
            guard failure != .cancelled else { return }
            logger.debug("Realtime address probe failed: \(String(describing: error), privacy: .public)")
            consecutiveFailures += 1
            if consecutiveFailures >= unavailableFailureThreshold {
                burstUntil = nil
                probeWasUnavailable = true
                await lookupService.markProbeUnavailable(failure)
            } else {
                boost()
            }
            return
        }
    }

    private func runLoop() async {
        var shouldRefreshMetadata = true
        while !Task.isCancelled {
            let cycleStarted = clock.now
            if shouldRefreshMetadata {
                shouldRefreshMetadata = false
                await refreshNow()
            } else {
                await pollNow()
            }
            let nextCycle = cycleStarted.advanced(by: currentInterval)
            let remaining = clock.now.duration(to: nextCycle)
            guard remaining > .zero else { continue }
            do {
                try await Task.sleep(for: remaining)
            } catch {
                break
            }
        }
    }

    private var currentInterval: Duration {
        if let burstUntil, clock.now < burstUntil { return burstInterval }
        return isLowPowerModeEnabled() ? lowPowerInterval : stableInterval
    }
}
