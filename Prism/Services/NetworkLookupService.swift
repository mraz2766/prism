import Foundation
import OSLog

actor NetworkLookupService {
    private let publicIPProvider: any PublicIPProviding
    private let geoProvider: any GeoIPProvider
    private let privacyProvider: any PrivacyClassifying
    private let countryLookup: any CountryLookingUp
    private let cache: NetworkInfoCache
    private let history: NetworkHistoryStore
    private let now: @Sendable () -> Date
    private let hardTimeout: Duration
    private let logger = Logger(subsystem: "com.mraz.prism", category: "network")

    private var currentStatus: NetworkStatus
    private var lastConfirmedInfo: NetworkInfo?
    private var privacyClassifications: [String: PrivacyClassification]
    private var locations: [String: CachedLocation]
    private var environmentGeneration = 0
    private var historyLocationsLoaded = false
    private var historyLoadTask: Task<[NetworkHistoryEntry], Never>?
    private var inflight: Inflight?
    private var retryState: MetadataRetry?
    private var statusBeforeVerification: NetworkStatus?
    private var cityLookupAddresses: Set<String> = []
    private var continuations: [UUID: AsyncStream<NetworkStatus>.Continuation] = [:]

    init(
        publicIPProvider: any PublicIPProviding,
        geoProvider: any GeoIPProvider,
        privacyProvider: any PrivacyClassifying,
        cache: NetworkInfoCache,
        history: NetworkHistoryStore,
        countryLookup: any CountryLookingUp = OfflineCountryLookup(),
        hardTimeout: Duration = .seconds(15),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.publicIPProvider = publicIPProvider
        self.geoProvider = geoProvider
        self.privacyProvider = privacyProvider
        self.countryLookup = countryLookup
        self.cache = cache
        self.history = history
        self.hardTimeout = hardTimeout
        self.now = now
        let cachedInfo = cache.loadInfo()
        currentStatus = .idle
        lastConfirmedInfo = cachedInfo
        locations = cache.loadLocations()
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
        currentStatus.retainedInfo ?? lastConfirmedInfo
    }

    func refreshMissingCity() async {
        guard !Task.isCancelled,
              case .online(let info) = currentStatus,
              info.location.city?.isEmpty != false,
              let address = info.addresses.preferredForLookup,
              !cityLookupAddresses.contains(address) else { return }

        let generation = environmentGeneration
        cityLookupAddresses.insert(address)
        defer { cityLookupAddresses.remove(address) }

        guard let geo = try? await geoProvider.lookup(ipAddress: address),
              generation == environmentGeneration,
              !Task.isCancelled,
              let city = geo.location.city,
              !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              case .online(let current) = currentStatus,
              current.addresses.preferredForLookup == address,
              current.location.city?.isEmpty != false,
              current.location.countryCode == geo.location.countryCode else { return }

        let enriched = NetworkInfo(
            addresses: current.addresses,
            location: geo.location,
            network: geo.network,
            privacy: current.privacy,
            providerIdentifier: geo.providerIdentifier,
            routeMode: current.routeMode,
            exitSource: current.exitSource,
            checkedAt: current.checkedAt,
            locationCheckedAt: now(),
            locationSource: .online
        )
        saveSuccessfulLocation(enriched, address: address)
        lastConfirmedInfo = enriched
        cache.saveInfo(enriched)
        emit(.online(enriched))
    }

    func markVerifying(_ observation: ExitObservation) {
        if case .verifying = currentStatus {} else {
            statusBeforeVerification = currentStatus
        }
        emit(.verifying(previous: currentStatus.retainedInfo, candidateAddress: observation.primaryAddress))
    }

    func cancelVerification() {
        guard case .verifying = currentStatus else { return }
        if let previous = statusBeforeVerification, previous != .idle {
            if case .locating(let info) = previous, inflight == nil {
                emit(.locationUnavailable(info, reason: .cancelled))
            } else {
                emit(previous)
            }
        } else if let info = lastConfirmedInfo {
            emit(restoredStatus(for: info))
        } else {
            emit(.idle)
        }
        statusBeforeVerification = nil
    }

    func cancelRefreshForEnvironmentChange() {
        environmentGeneration &+= 1
        inflight?.task.cancel()
        inflight = nil
        if let retryState {
            // Reset the delay after an environment change without losing the metadata failure.
            self.retryState = MetadataRetry(
                address: retryState.address, attempts: 0, nextAttemptAt: now(), failure: retryState.failure
            )
        }
        // Cancellation must leave a recoverable state, not an orphaned “locating” indicator.
        switch currentStatus {
        case .locating(let info):
            if let address = info.addresses.preferredForLookup {
                retryState = MetadataRetry(address: address, attempts: 0, nextAttemptAt: now(), failure: .cancelled)
            }
            emit(.locationUnavailable(info, reason: .cancelled))
        case .loading(let previous):
            if let previous { emit(.stale(previous, reason: .cancelled)) }
            else { emit(.failed(.cancelled)) }
        default: break
        }
        if case .locating(let info) = statusBeforeVerification {
            statusBeforeVerification = .locationUnavailable(info, reason: .cancelled)
        }
    }

    @discardableResult
    func refresh(
        observation: ExitObservation? = nil,
        showLoading: Bool = false,
        respectRetryBackoff: Bool = false
    ) async -> NetworkStatus {
        let generation = environmentGeneration
        await loadHistoricalLocations()
        guard generation == environmentGeneration, !Task.isCancelled else { return currentStatus }
        if let inflight {
            if observation == nil || inflight.address == observation?.primaryAddress {
                _ = try? await inflight.task.value
                return currentStatus
            }
            inflight.task.cancel()
            self.inflight = nil
        }
        // The exit probe continues at its normal cadence while metadata waits for its retry window.
        if respectRetryBackoff, let observation, observation.preResolvedGeo == nil,
           let retryState, retryState.address == observation.primaryAddress,
           now() < retryState.nextAttemptAt {
            let info = observedInfo(observation.addresses, primaryAddress: observation.primaryAddress, observation: observation)
            lastConfirmedInfo = info
            emit(.locationUnavailable(info, reason: retryState.failure))
            return currentStatus
        }
        let visiblePrevious = currentStatus.info
        let fallbackInfo = currentStatus.retainedInfo ?? lastConfirmedInfo
        if showLoading && observation == nil { emit(.loading(previous: visiblePrevious)) }

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
                let observed = try await self.publishObservation(
                    addresses, primaryAddress: lookupIP, observation: observation, requestID: requestID
                )
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
                return NetworkInfo(
                    addresses: addresses,
                    location: resolvedGeo.location,
                    network: resolvedGeo.network,
                    privacy: resolvedPrivacy,
                    providerIdentifier: resolvedGeo.providerIdentifier,
                    routeMode: observed.routeMode,
                    exitSource: observed.exitSource,
                    checkedAt: observed.checkedAt,
                    locationCheckedAt: self.now(),
                    locationSource: .online
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
            retryState = nil
            saveSuccessfulLocation(info, address: inflight?.address ?? info.addresses.preferredForLookup)
            lastConfirmedInfo = info
            cache.saveInfo(info)
            _ = await history.recordIfChanged(info)
            guard inflight?.id == requestID else { return currentStatus }
            emit(.online(info))
        } catch {
            // A cancelled or late result from a superseded network must never overwrite the new exit.
            guard inflight?.id == requestID else { return currentStatus }
            let failure = NetworkFailure.map(error)
            if let observed = inflight?.info {
                scheduleRetry(address: observed.addresses.preferredForLookup, failure: failure)
                lastConfirmedInfo = observed
                cache.saveInfo(observed)
                emit(.locationUnavailable(observed, reason: failure))
                if observed.hasLocation { _ = await history.recordIfChanged(observed) }
                if failure != .cancelled {
                    logger.info("Background location refresh failed: \(String(describing: failure), privacy: .public)")
                }
            } else {
                logger.error("Exit refresh failed: \(String(describing: failure), privacy: .public)")
                if let fallbackInfo {
                    emit(.stale(fallbackInfo, reason: failure))
                } else {
                    emit(.failed(failure))
                }
            }
        }
        return currentStatus
    }

    func markOffline() {
        environmentGeneration &+= 1
        inflight?.task.cancel()
        inflight = nil
        emit(.offline(previous: currentStatus.retainedInfo ?? lastConfirmedInfo))
    }

    func markProbeUnavailable(_ failure: NetworkFailure) {
        guard failure != .cancelled else { return }
        if case .offline = currentStatus { return }
        if let fallbackInfo = currentStatus.retainedInfo ?? lastConfirmedInfo {
            emit(.stale(fallbackInfo, reason: failure))
        } else {
            emit(.failed(failure))
        }
    }

    func restoreProbeAvailability(_ observation: ExitObservation) async -> Bool {
        let generation = environmentGeneration
        await loadHistoricalLocations()
        guard generation == environmentGeneration else { return false }
        guard let fallbackInfo = currentStatus.retainedInfo ?? lastConfirmedInfo,
              fallbackInfo.addresses.preferredForLookup == observation.primaryAddress else { return false }
        let restored = observedInfo(observation.addresses, primaryAddress: observation.primaryAddress, observation: observation)
        lastConfirmedInfo = restored
        cache.saveInfo(restored)
        emit(restoredStatus(for: restored))
        return true
    }

    private func restoredStatus(for info: NetworkInfo) -> NetworkStatus {
        if let retryState, retryState.address == info.addresses.preferredForLookup {
            return .locationUnavailable(info, reason: retryState.failure)
        }
        return info.hasLocation ? .online(info) : .locationUnavailable(info, reason: .serviceUnavailable)
    }

    private func observedInfo(
        _ addresses: IPAddressSet,
        primaryAddress: String,
        observation: ExitObservation?
    ) -> NetworkInfo {
        let previous = currentStatus.retainedInfo ?? lastConfirmedInfo
        let key = IPAddressKey.normalized(primaryAddress)
        let matching = key != nil && previous?.addresses.preferredForLookup.flatMap(IPAddressKey.normalized) == key
            ? previous : nil
        let cached = key.flatMap { locations[$0] }
        let offlineCountry = countryLookup.countryCode(for: primaryAddress)
        // Keep a recent, exact-IP success. Older records remain available if the country database has no answer.
        let recentCached = cached.flatMap { entry -> CachedLocation? in
            guard let recordedAt = entry.recordedAt else { return offlineCountry == nil ? entry : nil }
            return now().timeIntervalSince(recordedAt) <= 30 * 24 * 60 * 60 || offlineCountry == nil ? entry : nil
        }
        let location: LocationInfo
        let network: NetworkIdentity
        let source: LocationSource
        let provider: String
        let locationDate: Date?
        if let recentCached {
            location = recentCached.location
            network = recentCached.network
            source = .history
            provider = recentCached.providerIdentifier
            locationDate = recentCached.recordedAt
        } else if let offlineCountry {
            location = LocationInfo(countryCode: offlineCountry, region: nil, city: nil, timezone: nil, latitude: nil, longitude: nil)
            network = .unavailable
            source = .offline
            provider = "DB-IP Country Lite"
            locationDate = nil
        } else {
            location = .unavailable
            network = .unavailable
            source = .unknown
            provider = ""
            locationDate = nil
        }
        return NetworkInfo(
            addresses: addresses,
            location: location,
            network: network,
            privacy: privacyClassifications[primaryAddress] ?? .unavailable,
            providerIdentifier: provider,
            routeMode: observation?.routeMode ?? matching?.routeMode ?? .unknown,
            exitSource: observation?.source ?? matching?.exitSource ?? .unknown,
            checkedAt: observation?.observedAt ?? now(),
            locationCheckedAt: locationDate,
            locationSource: source
        )
    }

    private func loadHistoricalLocations() async {
        guard !historyLocationsLoaded else { return }
        let task = historyLoadTask ?? Task { [history] in await history.snapshot() }
        historyLoadTask = task
        let entries = await task.value
        guard !historyLocationsLoaded else { return }
        for entry in entries {
            guard let address = entry.addresses.preferredForLookup,
                  let key = IPAddressKey.normalized(address) else { continue }
            let candidate = CachedLocation(historyEntry: entry)
            guard candidate.isCacheable else { continue }
            if let existing = locations[key],
               (existing.recordedAt ?? .distantPast) >= (candidate.recordedAt ?? .distantPast) { continue }
            locations[key] = candidate
        }
        cache.saveLocations(locations)
        locations = cache.loadLocations()
        historyLocationsLoaded = true
        historyLoadTask = nil
    }

    private func saveSuccessfulLocation(_ info: NetworkInfo, address: String?) {
        guard let address, let key = IPAddressKey.normalized(address) else { return }
        let entry = CachedLocation(info: info)
        guard entry.isCacheable else { return }
        locations[key] = entry
        cache.saveLocations(locations)
        locations = cache.loadLocations()
    }

    private func publishObservation(
        _ addresses: IPAddressSet,
        primaryAddress: String,
        observation: ExitObservation?,
        requestID: UUID
    ) throws -> NetworkInfo {
        try Task.checkCancellation()
        guard inflight?.id == requestID else { throw CancellationError() }
        let info = observedInfo(addresses, primaryAddress: primaryAddress, observation: observation)
        if retryState?.address != primaryAddress { retryState = nil }
        inflight?.address = primaryAddress
        inflight?.info = info
        lastConfirmedInfo = info
        statusBeforeVerification = nil
        emit(.locating(info))
        return info
    }

    private func scheduleRetry(address: String?, failure: NetworkFailure) {
        guard let address, failure != .cancelled else { return }
        let attempts = (retryState?.address == address ? retryState?.attempts ?? 0 : 0) + 1
        let delays: [TimeInterval] = [5, 15, 30]
        var nextAttemptAt = now().addingTimeInterval(delays[min(attempts - 1, delays.count - 1)])
        if case .coolingDown(let until) = failure {
            nextAttemptAt = max(nextAttemptAt, until)
        }
        retryState = MetadataRetry(address: address, attempts: attempts, nextAttemptAt: nextAttemptAt, failure: failure)
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

    private struct MetadataRetry {
        let address: String
        let attempts: Int
        let nextAttemptAt: Date
        let failure: NetworkFailure
    }

    private struct Inflight {
        let id: UUID
        var address: String?
        let task: Task<NetworkInfo, Error>
        var info: NetworkInfo?
    }
}
