import Foundation

struct ProviderHealthSnapshot: Identifiable, Equatable, Sendable {
    let identifier: String
    let consecutiveFailures: Int
    let lastLatencyMilliseconds: Int?
    let lastSuccessAt: Date?
    let circuitOpenUntil: Date?

    var id: String { identifier }
    var isCircuitOpen: Bool { circuitOpenUntil.map { $0 > .now } ?? false }
}

actor ProviderHealthRegistry {
    private struct State: Sendable {
        var consecutiveFailures = 0
        var lastLatencyMilliseconds: Int?
        var lastSuccessAt: Date?
        var circuitOpenUntil: Date?
    }

    private let failureThreshold: Int
    private let cooldown: TimeInterval
    private var states: [String: State] = [:]

    init(failureThreshold: Int = 2, cooldown: TimeInterval = 30) {
        self.failureThreshold = failureThreshold
        self.cooldown = cooldown
    }

    func canAttempt(_ identifier: String, now: Date = .now) -> Bool {
        guard let openUntil = states[identifier]?.circuitOpenUntil else { return true }
        return openUntil <= now
    }

    func recordSuccess(_ identifier: String, latency: Duration, at date: Date = .now) {
        var state = states[identifier] ?? State()
        state.consecutiveFailures = 0
        state.lastLatencyMilliseconds = Self.milliseconds(latency)
        state.lastSuccessAt = date
        state.circuitOpenUntil = nil
        states[identifier] = state
    }

    func recordFailure(
        _ identifier: String,
        failure: NetworkFailure,
        latency: Duration,
        at date: Date = .now
    ) {
        guard failure != .cancelled else { return }
        var state = states[identifier] ?? State()
        state.consecutiveFailures += 1
        state.lastLatencyMilliseconds = Self.milliseconds(latency)
        if state.consecutiveFailures >= failureThreshold {
            state.circuitOpenUntil = date.addingTimeInterval(cooldown)
        }
        states[identifier] = state
    }

    func snapshots(order: [String] = []) -> [ProviderHealthSnapshot] {
        let identifiers = order + states.keys.filter { !order.contains($0) }.sorted()
        return identifiers.map { identifier in
            let state = states[identifier] ?? State()
            return ProviderHealthSnapshot(
                identifier: identifier,
                consecutiveFailures: state.consecutiveFailures,
                lastLatencyMilliseconds: state.lastLatencyMilliseconds,
                lastSuccessAt: state.lastSuccessAt,
                circuitOpenUntil: state.circuitOpenUntil
            )
        }
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        let components = duration.components
        let seconds = Double(components.seconds)
        let fraction = Double(components.attoseconds) / 1_000_000_000_000_000_000
        return max(0, Int(((seconds + fraction) * 1_000).rounded()))
    }
}
