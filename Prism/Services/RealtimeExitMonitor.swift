import Foundation
import OSLog

@MainActor
final class RealtimeExitMonitor {
    private let probe: any ExitAddressProbing
    private let lookupService: NetworkLookupService
    private let stableInterval: Duration
    private let burstInterval: Duration
    private let burstDuration: Duration
    private let clock = ContinuousClock()
    private let logger = Logger(subsystem: "com.mraz.prism", category: "realtime-exit")

    private var loopTask: Task<Void, Never>?
    private var isPaused = false
    private var burstUntil: ContinuousClock.Instant?
    private var stabilizer = ExitStabilizer()

    init(
        probe: any ExitAddressProbing,
        lookupService: NetworkLookupService,
        interval: Duration = .seconds(1),
        retryBackoff: Duration = .seconds(5),
        burstInterval: Duration = .milliseconds(250),
        burstDuration: Duration = .seconds(5)
    ) {
        self.probe = probe
        self.lookupService = lookupService
        self.stableInterval = interval
        self.burstInterval = burstInterval
        self.burstDuration = burstDuration
        _ = retryBackoff
    }

    func start() {
        guard loopTask == nil else { return }
        isPaused = false
        loopTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        burstUntil = nil
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

    func pollNow() async {
        await observeAndApply(refreshUnchanged: false, showLoading: false)
    }

    func refreshNow(showLoading: Bool = false) async {
        await observeAndApply(refreshUnchanged: true, showLoading: showLoading)
    }

    private func observeAndApply(refreshUnchanged: Bool, showLoading: Bool) async {
        guard !isPaused, !Task.isCancelled else { return }

        do {
            let observation = try await probe.observeExit()
            let status = await lookupService.snapshot()
            switch stabilizer.evaluate(observation, currentInfo: status.info) {
            case .unchanged:
                if refreshUnchanged {
                    _ = await lookupService.refresh(observation: observation, showLoading: showLoading)
                }
            case .cancelled:
                await lookupService.cancelVerification()
                if refreshUnchanged {
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
            if NetworkFailure.map(error) != .cancelled {
                logger.debug("Realtime address probe failed: \(String(describing: error), privacy: .public)")
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
        guard let burstUntil, clock.now < burstUntil else { return stableInterval }
        return burstInterval
    }
}
