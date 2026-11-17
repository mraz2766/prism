import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class NetworkTestViewModel {
    enum Phase: String, Equatable { case idle, running, completed, cancelled, invalidated }

    private(set) var results = NetworkTestTarget.defaults.map { NetworkTestResult(target: $0) }
    private(set) var phase: Phase = .idle
    private(set) var activeTargets: Set<String> = []
    private(set) var webRTC: WebRTCReport?
    private(set) var webRTCRunning = false
    private(set) var startedAt: Date?
    private(set) var finishedAt: Date?
    private(set) var httpAddresses = IPAddressSet(ipv4: nil, ipv6: nil)
    var selectedTargetID = "google"
    @ObservationIgnored private let probe: any NetworkTestProbing
    @ObservationIgnored private let rtc: any WebRTCProbing
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var observedAddresses = IPAddressSet(ipv4: nil, ipv6: nil)

    static let sampleCount = 3
    var isRunning: Bool { phase == .running }
    var completedSamples: Int { results.reduce(0) { $0 + $1.samples.count } }
    var totalSamples: Int { results.count * Self.sampleCount }
    var progress: Double { Double(completedSamples) / Double(totalSamples) }
    var selectedResult: NetworkTestResult { results.first { $0.id == selectedTargetID } ?? results[0] }

    init(probe: any NetworkTestProbing = NetworkTestService(), rtc: any WebRTCProbing = WebRTCProbe()) {
        self.probe = probe
        self.rtc = rtc
    }

    @discardableResult
    func start(httpAddresses: IPAddressSet) -> Task<Void, Never> {
        stop()
        let id = UUID()
        generation = id
        self.httpAddresses = httpAddresses
        observedAddresses = httpAddresses
        results = NetworkTestTarget.defaults.map { .init(target: $0) }
        webRTC = nil
        webRTCRunning = true
        startedAt = .now
        finishedAt = nil
        phase = .running
        let task = Task { [weak self, probe, rtc] in
            guard let self, generation == id, !Task.isCancelled else { return }
            async let ice: Void = collectICE(rtc, generation: id)
            do {
                for round in 1...Self.sampleCount {
                    // At most two site requests in flight. Failed samples still advance progress.
                    for offset in stride(from: 0, to: results.count, by: 2) {
                        try Task.checkCancellation()
                        let targets = results.dropFirst(offset).prefix(2).map(\.target)
                        guard generation == id else { return }
                        activeTargets = Set(targets.map(\.id))
                        try await withThrowingTaskGroup(of: (String, NetworkTestSample).self) { group in
                            for target in targets {
                                group.addTask { (target.id, try await probe.measure(target, round: round)) }
                            }
                            for try await (targetID, sample) in group {
                                guard generation == id, !Task.isCancelled else { continue }
                                if let index = results.firstIndex(where: { $0.id == targetID }) { results[index].samples.append(sample) }
                                activeTargets.remove(targetID)
                            }
                        }
                    }
                    if round < Self.sampleCount { try await Task.sleep(for: .milliseconds(180)) }
                }
                await ice
                guard generation == id, !Task.isCancelled else { return }
                phase = .completed
                finishedAt = .now
                activeTargets = []
                operation = nil
            } catch {
                guard generation == id else { return }
                stop()
            }
        }
        operation = task
        return task
    }

    private func collectICE(_ rtc: any WebRTCProbing, generation id: UUID) async {
        guard generation == id, !Task.isCancelled else { return }
        let report = await rtc.collect()
        guard generation == id, !Task.isCancelled else { return }
        webRTC = report
        webRTCRunning = false
    }

    func stop() {
        generation = UUID()
        operation?.cancel()
        operation = nil
        rtc.cancel()
        activeTargets = []
        webRTCRunning = false
        if isRunning {
            phase = .cancelled
            finishedAt = .now
            if webRTC == nil { webRTC = .init(outcome: .cancelled) }
        }
    }

    func invalidate(reason: String = "network environment") {
        guard phase != .idle, phase != .invalidated else { return }
        Logger(subsystem: "com.mraz.prism", category: "network-test").notice("Invalidated test: \(reason, privacy: .public)")
        stop()
        phase = .invalidated
    }

    func observedExitChanged(_ addresses: IPAddressSet) {
        guard phase == .running || phase == .completed || phase == .cancelled else { return }
        // A missing family is an incomplete observation, not evidence of a changed exit.
        // Keep the last known address per family so a later real change is still detected.
        let changed = [(observedAddresses.ipv4, addresses.ipv4), (observedAddresses.ipv6, addresses.ipv6)]
            .contains { previous, current in
                guard let previous = previous.flatMap(IPAddressKey.normalized),
                      let current = current.flatMap(IPAddressKey.normalized) else { return false }
                return previous != current
            }
        if changed {
            invalidate(reason: "confirmed address changed within the same IP family")
            return
        }
        observedAddresses = .init(
            ipv4: addresses.ipv4 ?? observedAddresses.ipv4,
            ipv6: addresses.ipv6 ?? observedAddresses.ipv6
        )
        // httpAddresses remains the test-start snapshot used for WebRTC assessment.
    }
}
