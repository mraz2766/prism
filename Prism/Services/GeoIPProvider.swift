import Foundation
import OSLog

protocol GeoIPProvider: Sendable {
    var identifier: String { get }
    func lookup(ipAddress: String) async throws -> GeoIPResult
}

struct FallbackGeoIPProvider: GeoIPProvider {
    let identifier: String
    private let providers: [any GeoIPProvider]
    private let health: ProviderHealthRegistry
    private let logger = Logger(subsystem: "com.mraz.prism", category: "geo-provider")

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
        try Task.checkCancellation()
        return try await withThrowingTaskGroup(of: ProviderAttempt.self) { group in
            for (index, provider) in providers.enumerated() {
                group.addTask {
                    do {
                        if let retryAt = await health.retryDate(for: provider.identifier) {
                            return .coolingDown(retryAt)
                        }
                        if index > 0 {
                            try await Task.sleep(for: .milliseconds(Int64(index * 300)))
                        }
                        try Task.checkCancellation()
                        let clock = ContinuousClock()
                        let startedAt = clock.now
                        do {
                            let result = try await provider.lookup(ipAddress: ipAddress)
                            try Task.checkCancellation()
                            await health.recordSuccess(
                                provider.identifier,
                                latency: startedAt.duration(to: clock.now)
                            )
                            return .success(result)
                        } catch {
                            let failure = Task.isCancelled ? .cancelled : NetworkFailure.map(error)
                            let latency = startedAt.duration(to: clock.now)
                            await health.recordFailure(
                                provider.identifier,
                                failure: failure,
                                latency: latency
                            )
                            if failure != .cancelled {
                                let milliseconds = Self.milliseconds(latency)
                                // Only provider identity, error category and duration are logged; never IP addresses.
                                logger.info("Geo provider \(provider.identifier, privacy: .public): \(String(describing: failure), privacy: .public), \(milliseconds) ms")
                            }
                            return .failure(failure)
                        }
                    } catch {
                        return .failure(NetworkFailure.map(error))
                    }
                }
            }

            var firstFailure: NetworkFailure?
            var earliestRetry: Date?
            var sawCancellation = false
            var countryOnlyResult: GeoIPResult?
            while let attempt = try await group.next() {
                switch attempt {
                case .success(let result):
                    if let city = result.location.city,
                       !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        group.cancelAll()
                        return result
                    }
                    if countryOnlyResult == nil { countryOnlyResult = result }
                case .failure(let failure):
                    switch failure {
                    case .cancelled: sawCancellation = true
                    case .notApplicable: break
                    case .coolingDown(let retryAt):
                        earliestRetry = min(earliestRetry ?? retryAt, retryAt)
                    default:
                        if firstFailure == nil { firstFailure = failure }
                    }
                case .coolingDown(let retryAt):
                    earliestRetry = min(earliestRetry ?? retryAt, retryAt)
                }
            }
            try Task.checkCancellation()
            if let countryOnlyResult { return countryOnlyResult }
            if let firstFailure { throw firstFailure }
            if let earliestRetry { throw NetworkFailure.coolingDown(until: earliestRetry) }
            if sawCancellation { throw NetworkFailure.cancelled }
            throw NetworkFailure.notApplicable
        }
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        let components = duration.components
        return max(0, Int(Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000))
    }

    private enum ProviderAttempt: Sendable {
        case success(GeoIPResult)
        case failure(NetworkFailure)
        case coolingDown(Date)
    }
}
