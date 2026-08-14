import Foundation

struct ExitStabilizer: Sendable {
    enum Decision: Equatable, Sendable {
        case unchanged
        case pending(ExitObservation)
        case confirmed(ExitObservation)
        case cancelled
    }

    private var pending: ExitObservation?
    private var pendingCount = 0

    mutating func evaluate(
        _ observation: ExitObservation,
        currentInfo: NetworkInfo?
    ) -> Decision {
        guard let currentInfo else {
            return advancePending(observation)
        }

        if currentInfo.addresses.ipv4 == observation.primaryAddress ||
            currentInfo.addresses.ipv6 == observation.primaryAddress {
            if currentInfo.routeMode == .unknown, observation.routeMode != .unknown {
                resetPending()
                return .confirmed(observation)
            }
            let hadPending = pending != nil
            resetPending()
            return hadPending ? .cancelled : .unchanged
        }

        if currentInfo.routeMode == observation.routeMode,
           observation.routeMode != .unknown {
            resetPending()
            return .confirmed(observation)
        }

        return advancePending(observation)
    }

    mutating func reset() {
        resetPending()
    }

    private mutating func advancePending(_ observation: ExitObservation) -> Decision {
        if pending?.routeMode == observation.routeMode,
           pending?.source == observation.source {
            pending = observation
            pendingCount += 1
        } else {
            pending = observation
            pendingCount = 1
        }

        guard pendingCount >= 2 else { return .pending(observation) }
        resetPending()
        return .confirmed(observation)
    }

    private mutating func resetPending() {
        pending = nil
        pendingCount = 0
    }
}
