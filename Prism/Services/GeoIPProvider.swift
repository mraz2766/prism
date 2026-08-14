import Foundation

protocol GeoIPProvider: Sendable {
    var identifier: String { get }
    func lookup(ipAddress: String) async throws -> GeoIPResult
}

struct FallbackGeoIPProvider: GeoIPProvider {
    let identifier: String
    private let providers: [any GeoIPProvider]
    private let health: ProviderHealthRegistry

    init(
        providers: [any GeoIPProvider],
        health: ProviderHealthRegistry = ProviderHealthRegistry()
    ) {
        precondition(!providers.isEmpty)
        self.providers = providers
        self.health = health
        identifier = providers.map(\.identifier).joined(separator: " → ")
    }

    func lookup(ipAddress: String) async throws -> GeoIPResult {
        try await withThrowingTaskGroup(of: ProviderAttempt.self) { group in
            for (index, provider) in providers.enumerated() {
                group.addTask {
                    do {
                        if index > 0 {
                            try await Task.sleep(for: .milliseconds(Int64(index * 300)))
                        }
                        guard await health.canAttempt(provider.identifier) else {
                            return .skipped
                        }
                        let clock = ContinuousClock()
                        let startedAt = clock.now
                        do {
                            let result = try await provider.lookup(ipAddress: ipAddress)
                            await health.recordSuccess(
                                provider.identifier,
                                latency: startedAt.duration(to: clock.now)
                            )
                            return .success(result)
                        } catch {
                            let failure = NetworkFailure.map(error)
                            await health.recordFailure(
                                provider.identifier,
                                failure: failure,
                                latency: startedAt.duration(to: clock.now)
                            )
                            return .failure(failure)
                        }
                    } catch {
                        return .failure(NetworkFailure.map(error))
                    }
                }
            }

            var firstFailure: NetworkFailure?
            while let attempt = try await group.next() {
                switch attempt {
                case .success(let result):
                    group.cancelAll()
                    return result
                case .failure(let failure):
                    if failure != .cancelled, firstFailure == nil { firstFailure = failure }
                case .skipped:
                    continue
                }
            }
            try Task.checkCancellation()
            throw firstFailure ?? NetworkFailure.serviceUnavailable
        }
    }

    private enum ProviderAttempt: Sendable {
        case success(GeoIPResult)
        case failure(NetworkFailure)
        case skipped
    }
}
