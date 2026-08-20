import Foundation
import OSLog

actor NetworkLookupService {
    private let publicIPProvider: any PublicIPProviding
    private let geoProvider: any GeoIPProvider
    private let privacyProvider: any PrivacyClassifying
    private let cache: NetworkInfoCache
    private let history: NetworkHistoryStore
    private let hardTimeout: Duration
    private let logger = Logger(subsystem: "com.mraz.prism", category: "network")

    private var currentStatus: NetworkStatus
    private var lastConfirmedInfo: NetworkInfo?
    private var privacyClassifications: [String: PrivacyClassification]
    private var inflight: Inflight?
    private var continuations: [UUID: AsyncStream<NetworkStatus>.Continuation] = [:]

    init(
        publicIPProvider: any PublicIPProviding,
        geoProvider: any GeoIPProvider,
        privacyProvider: any PrivacyClassifying,
        cache: NetworkInfoCache,
        history: NetworkHistoryStore,
        hardTimeout: Duration = .seconds(15)
    ) {
        self.publicIPProvider = publicIPProvider
        self.geoProvider = geoProvider
        self.privacyProvider = privacyProvider
        self.cache = cache
        self.history = history
        self.hardTimeout = hardTimeout
        let cachedInfo = cache.loadInfo()
        currentStatus = .idle
        lastConfirmedInfo = cachedInfo
        privacyClassifications = cache.loadPrivacyClassifications()
    }

    nonisolated func stream() -> AsyncStream<NetworkStatus> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.register(id: id, continuation: continuation) }
            continuation.onTermination = { @Sendable _ in
                Task { await self.unregister(id: id) }
            }
        }
    }

    func snapshot() -> NetworkStatus { currentStatus }

    func comparisonInfo() -> NetworkInfo? {
        currentStatus.info ?? lastConfirmedInfo
    }

    func markVerifying(_ observation: ExitObservation) {
        emit(.verifying(previous: currentStatus.info, candidateAddress: observation.primaryAddress))
    }

    func cancelVerification() {
        guard case .verifying(let previous, _) = currentStatus else { return }
        if let previous {
            emit(.online(previous))
        } else if let lastConfirmedInfo {
            emit(.online(lastConfirmedInfo))
        } else {
            emit(.idle)
        }
    }

    @discardableResult
    func refresh(
        observation: ExitObservation? = nil,
        showLoading: Bool = false
    ) async -> NetworkStatus {
        if let inflight {
            if observation == nil || inflight.address == observation?.primaryAddress {
                _ = try? await inflight.task.value
                return currentStatus
            }
            inflight.task.cancel()
        }
        let visiblePrevious = currentStatus.info
        let fallbackInfo = visiblePrevious ?? lastConfirmedInfo
        if showLoading { emit(.loading(previous: visiblePrevious)) }

        let publicIPProvider = self.publicIPProvider
        let geoProvider = self.geoProvider
        let privacyProvider = self.privacyProvider
        let existingPrivacyClassifications = privacyClassifications
        let requestID = UUID()
        let task = Task<NetworkInfo, Error> {
            try await Self.withTimeout(duration: hardTimeout) {
                let addresses: IPAddressSet
                if let observation {
                    addresses = observation.addresses
                } else {
                    addresses = try await publicIPProvider.fetchAddresses()
                }
                guard let lookupIP = observation?.primaryAddress ?? addresses.preferredForLookup else {
                    throw NetworkFailure.serviceUnavailable
                }
                async let privacy = Self.resolvePrivacy(
                    cached: existingPrivacyClassifications[lookupIP],
                    provider: privacyProvider,
                    ipAddress: lookupIP
                )
                let resolvedGeo: GeoIPResult
                if let preResolved = observation?.preResolvedGeo {
                    resolvedGeo = preResolved
                } else {
                    resolvedGeo = try await geoProvider.lookup(ipAddress: lookupIP)
                }
                let resolvedPrivacy = await privacy
                let preservesPreviousRoute = fallbackInfo?.addresses.ipv4 == lookupIP || fallbackInfo?.addresses.ipv6 == lookupIP
                return NetworkInfo(
                    addresses: addresses,
                    location: resolvedGeo.location,
                    network: resolvedGeo.network,
                    privacy: resolvedPrivacy,
                    providerIdentifier: resolvedGeo.providerIdentifier,
                    routeMode: observation?.routeMode ?? (preservesPreviousRoute ? fallbackInfo?.routeMode : nil) ?? .unknown,
                    exitSource: observation?.source ?? (preservesPreviousRoute ? fallbackInfo?.exitSource : nil) ?? .unknown,
                    checkedAt: .now
                )
            }
        }
        inflight = Inflight(id: requestID, address: observation?.primaryAddress, task: task)
        defer {
            if inflight?.id == requestID { inflight = nil }
        }

        do {
            let info = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            guard inflight?.id == requestID else { return currentStatus }
            if let lookupIP = info.addresses.preferredForLookup,
               privacyClassifications[lookupIP] == nil {
                privacyClassifications[lookupIP] = info.privacy
                cache.savePrivacyClassifications(privacyClassifications)
            }
            lastConfirmedInfo = info
            cache.saveInfo(info)
            _ = await history.recordIfChanged(info)
            emit(.online(info))
        } catch {
            let failure = NetworkFailure.map(error)
            if failure == .cancelled, inflight?.id != requestID { return currentStatus }
            logger.error("Refresh failed: \(String(describing: failure), privacy: .public)")
            if let fallbackInfo {
                emit(.stale(fallbackInfo, reason: failure))
            } else {
                emit(.failed(failure))
            }
        }
        return currentStatus
    }

    func markOffline() {
        emit(.offline(previous: currentStatus.info ?? lastConfirmedInfo))
    }

    private static func bestEffortPrivacy(
        provider: any PrivacyClassifying,
        ipAddress: String
    ) async -> PrivacyClassification {
        (try? await provider.classify(ipAddress: ipAddress)) ?? .unavailable
    }

    private static func resolvePrivacy(
        cached: PrivacyClassification?,
        provider: any PrivacyClassifying,
        ipAddress: String
    ) async -> PrivacyClassification {
        if let cached { return cached }
        return await bestEffortPrivacy(provider: provider, ipAddress: ipAddress)
    }

    private static func withTimeout<T: Sendable>(
        duration: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw NetworkFailure.timeout
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw NetworkFailure.other }
            return first
        }
    }

    private func register(id: UUID, continuation: AsyncStream<NetworkStatus>.Continuation) {
        continuations[id] = continuation
        continuation.yield(currentStatus)
    }

    private func unregister(id: UUID) { continuations.removeValue(forKey: id) }

    private func emit(_ status: NetworkStatus) {
        currentStatus = status
        continuations.values.forEach { $0.yield(status) }
    }

    private struct Inflight {
        let id: UUID
        let address: String?
        let task: Task<NetworkInfo, Error>
    }
}
