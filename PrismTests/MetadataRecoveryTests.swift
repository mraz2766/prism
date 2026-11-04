import XCTest
@testable import Prism

final class MetadataRecoveryTests: XCTestCase {
    func testNewExitIsPublishedBeforeSlowLocationCompletes() async {
        let geo = SuspendedMetadataProvider()
        let service = makeService(geo: geo, cached: cachedInfo())
        let newExit = exit("198.51.100.20")
        let task = Task { await service.refresh(observation: newExit) }
        await geo.waitUntilStarted()

        let pending = await service.snapshot()
        let comparison = await service.comparisonInfo()
        guard case .locating(let info) = pending else {
            await geo.finish(.failure(.timeout))
            _ = await task.value
            return XCTFail("The new IP must be visible while its location is still pending")
        }
        XCTAssertEqual(info.addresses, newExit.addresses)
        XCTAssertFalse(info.hasLocation)
        XCTAssertNil(info.location.city)
        XCTAssertNil(info.locationCheckedAt)
        XCTAssertEqual(comparison?.addresses, newExit.addresses)

        await geo.finish(.failure(.timeout))
        let failed = await task.value
        guard case .locationUnavailable(let retained, let failure) = failed else {
            return XCTFail("Only location lookup should fail after the IP is known")
        }
        XCTAssertEqual(retained.addresses, newExit.addresses)
        XCTAssertFalse(retained.hasLocation)
        XCTAssertEqual(failure, .timeout)
    }

    func testEnvironmentChangeCancellationLeavesLocationRecoverableForTheSameExit() async {
        let geo = SuspendedMetadataProvider()
        let service = makeService(geo: geo)
        let observed = exit("198.51.100.20")
        let firstRefresh = Task { await service.refresh(observation: observed) }
        await geo.waitUntilStarted()
        let locating = await service.snapshot()
        guard case .locating = locating else {
            await geo.finish(.failure(.cancelled))
            _ = await firstRefresh.value
            return XCTFail("Expected an in-flight location lookup")
        }

        await service.cancelRefreshForEnvironmentChange()
        let cancelled = await service.snapshot()
        XCTAssertTrue(cancelled.needsRecoveryRefresh)
        guard case .locationUnavailable(let retained, .cancelled) = cancelled else {
            await geo.finish(.failure(.cancelled))
            _ = await firstRefresh.value
            return XCTFail("Environment changes must not leave an orphaned locating state")
        }
        XCTAssertEqual(retained.addresses, observed.addresses)
        await geo.finish(.failure(.cancelled))
        _ = await firstRefresh.value

        let retry = Task { await service.refresh(observation: observed, respectRetryBackoff: true) }
        await geo.waitUntilStarted()
        await geo.finish(.success(result()))
        let recovered = await retry.value
        guard case .online(let info) = recovered else {
            return XCTFail("The same exit must be able to retry after cancellation")
        }
        XCTAssertEqual(info.addresses, observed.addresses)
        XCTAssertEqual(info.location.countryCode, "JP")
    }

    func testSameExitRetainsLocationAndItsOriginalTimestampOnFailure() async {
        let original = cachedInfo()
        let geo = SequenceMetadataProvider(results: [.failure(.timeout)])
        let service = makeService(geo: geo, cached: original)
        let observed = exit(original.addresses.ipv4!, at: Date(timeIntervalSince1970: 2_000))

        let status = await service.refresh(observation: observed)

        guard case .locationUnavailable(let info, _) = status else {
            return XCTFail("Expected a location-only failure")
        }
        XCTAssertEqual(info.location, original.location)
        XCTAssertEqual(info.locationCheckedAt, original.locationCheckedAt)
        XCTAssertEqual(info.checkedAt, observed.observedAt)
        XCTAssertNotEqual(info.locationCheckedAt, info.checkedAt)
    }

    func testAutomaticMetadataRetriesBackOffFiveFifteenAndThirtySecondsThenRecover() async {
        let clock = MetadataTestClock()
        let geo = SequenceMetadataProvider(results: [
            .failure(.timeout), .failure(.timeout), .failure(.timeout), .success(result())
        ])
        let service = makeService(geo: geo, clock: clock)
        let observed = exit("198.51.100.20")
        _ = await service.refresh(observation: observed, respectRetryBackoff: true)
        var expectedCalls = 1

        for delay in [5.0, 15.0, 30.0] {
            clock.advance(by: delay - 0.1)
            _ = await service.refresh(observation: observed, respectRetryBackoff: true)
            let callsBeforeDeadline = await geo.callCount
            XCTAssertEqual(callsBeforeDeadline, expectedCalls, "Polling must not re-query metadata during backoff")
            clock.advance(by: 0.1)
            _ = await service.refresh(observation: observed, respectRetryBackoff: true)
            expectedCalls += 1
            let callsAtDeadline = await geo.callCount
            XCTAssertEqual(callsAtDeadline, expectedCalls)
        }
        guard case .online(let info) = await service.snapshot() else {
            return XCTFail("The successful retry must recover to online")
        }
        XCTAssertEqual(info.location.countryCode, "JP")
    }

    func testDifferentExitBypassesPreviousExitBackoff() async {
        let geo = SequenceMetadataProvider(results: [.failure(.timeout), .success(result())])
        let service = makeService(geo: geo)
        _ = await service.refresh(observation: exit("198.51.100.20"), respectRetryBackoff: true)
        let newExit = exit("198.51.100.21")

        let status = await service.refresh(observation: newExit, respectRetryBackoff: true)

        let calls = await geo.callCount
        XCTAssertEqual(calls, 2)
        guard case .online(let info) = status else { return XCTFail("New exits must be queried immediately") }
        XCTAssertEqual(info.addresses, newExit.addresses)
    }

    func testManualRefreshAndNetworkChangeCanRetryBeforeBackoffExpires() async {
        let geo = SequenceMetadataProvider(results: [
            .failure(.timeout), .failure(.timeout), .success(result())
        ])
        let service = makeService(geo: geo)
        let observed = exit("198.51.100.20")
        _ = await service.refresh(observation: observed, respectRetryBackoff: true)
        _ = await service.refresh(observation: observed, showLoading: true)
        let manualCalls = await geo.callCount
        XCTAssertEqual(manualCalls, 2)

        await service.cancelRefreshForEnvironmentChange()
        let status = await service.refresh(observation: observed, respectRetryBackoff: true)
        let callsAfterNetworkChange = await geo.callCount
        XCTAssertEqual(callsAfterNetworkChange, 3)
        guard case .online = status else { return XCTFail("Network changes must reset metadata backoff") }
    }

    func testProviderCooldownDelaysRetryUntilItsRecoveryTime() async {
        let clock = MetadataTestClock()
        let until = clock.now().addingTimeInterval(40)
        let geo = SequenceMetadataProvider(results: [.failure(.coolingDown(until: until)), .success(result())])
        let service = makeService(geo: geo, clock: clock)
        let observed = exit("198.51.100.20")
        _ = await service.refresh(observation: observed, respectRetryBackoff: true)

        clock.advance(by: 39)
        _ = await service.refresh(observation: observed, respectRetryBackoff: true)
        let callsDuringCooldown = await geo.callCount
        XCTAssertEqual(callsDuringCooldown, 1)
        clock.advance(by: 1)
        let status = await service.refresh(observation: observed, respectRetryBackoff: true)
        let callsAfterCooldown = await geo.callCount
        XCTAssertEqual(callsAfterCooldown, 2)
        guard case .online = status else { return XCTFail("Retry should resume after the provider cools down") }
    }

    func testProbeRecoveryDoesNotMislabelMissingLocationAsOnline() async {
        let geo = SequenceMetadataProvider(results: [.failure(.timeout)])
        let service = makeService(geo: geo)
        let observed = exit("198.51.100.20")
        _ = await service.refresh(observation: observed)
        await service.markProbeUnavailable(.serviceUnavailable)

        let restored = await service.restoreProbeAvailability(observed)
        let status = await service.snapshot()

        XCTAssertTrue(restored)
        guard case .locationUnavailable(let info, let reason) = status else {
            return XCTFail("A recovered address probe must preserve the location failure")
        }
        XCTAssertEqual(reason, .timeout)
        XCTAssertFalse(info.hasLocation)
        XCTAssertEqual(info.addresses, observed.addresses)
    }

    func testMonitorKeepsProbingWithoutRepeatingFailedMetadataOrConfirmingSameExit() async {
        let geo = SequenceMetadataProvider(results: [.failure(.timeout)])
        let service = makeService(geo: geo, cached: cachedInfo())
        let observed = exit("198.51.100.20")
        let probe = RepeatingMetadataTestProbe(observed)
        let monitor = RealtimeExitMonitor(probe: probe, lookupService: service)

        for _ in 0..<5 { await monitor.pollNow() }

        let probes = await probe.callCount
        let metadataCalls = await geo.callCount
        let status = await service.snapshot()
        XCTAssertEqual(probes, 5)
        XCTAssertEqual(metadataCalls, 1)
        guard case .locationUnavailable(let info, _) = status else {
            return XCTFail("Repeated observations of the same exit must retain its partial result")
        }
        XCTAssertEqual(info.addresses, observed.addresses)
    }

    func testCancelledExitVerificationRestoresLocationFailure() async {
        let geo = SequenceMetadataProvider(results: [.failure(.timeout)])
        let service = makeService(geo: geo)
        _ = await service.refresh(observation: exit("198.51.100.20"))
        await service.markVerifying(exit("198.51.100.21"))
        await service.cancelVerification()

        let status = await service.snapshot()
        guard case .locationUnavailable(let info, .timeout) = status else {
            return XCTFail("Cancelling a candidate must not turn partial metadata into online status")
        }
        XCTAssertEqual(info.addresses.ipv4, "198.51.100.20")
    }

    func testEnvironmentChangeAndProbeRecoveryPreserveSameIPLocationFailure() async {
        let original = cachedInfo()
        let service = makeService(geo: SequenceMetadataProvider(results: [.failure(.timeout)]), cached: original)
        let observed = exit(original.addresses.ipv4!)
        _ = await service.refresh(observation: observed)
        await service.cancelRefreshForEnvironmentChange()
        await service.markOffline()
        _ = await service.restoreProbeAvailability(observed)

        guard case .locationUnavailable(let info, .timeout) = await service.snapshot() else {
            return XCTFail("Recovering the address probe must not clear a previous metadata failure")
        }
        XCTAssertEqual(info.locationCheckedAt, original.locationCheckedAt)
    }

    private func makeService(
        geo: any GeoIPProvider,
        cached: NetworkInfo? = nil,
        clock: MetadataTestClock = MetadataTestClock()
    ) -> NetworkLookupService {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = NetworkInfoCache(directory: directory)
        if let cached { cache.saveInfo(cached) }
        return NetworkLookupService(
            publicIPProvider: MetadataPublicIPProvider(),
            geoProvider: geo,
            privacyProvider: MetadataPrivacyProvider(),
            cache: cache,
            history: NetworkHistoryStore(fileURL: directory.appendingPathComponent("history.json"), settlingDelay: .zero),
            now: { clock.now() }
        )
    }

    private func exit(_ ip: String, at date: Date = Date(timeIntervalSince1970: 2_000)) -> ExitObservation {
        ExitObservation(
            addresses: IPAddressSet(ipv4: ip, ipv6: nil),
            source: .overseasIPv4,
            routeMode: .proxy,
            observedAt: date
        )
    }

    private func cachedInfo() -> NetworkInfo {
        NetworkInfo(
            addresses: IPAddressSet(ipv4: "198.51.100.10", ipv6: nil),
            location: NetworkInfo.preview.location,
            network: NetworkInfo.preview.network,
            privacy: .notDetected,
            providerIdentifier: "fixture",
            routeMode: .proxy,
            exitSource: .overseasIPv4,
            checkedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func result() -> GeoIPResult {
        GeoIPResult(
            location: LocationInfo(countryCode: "JP", region: "Tokyo", city: "Tokyo", timezone: "Asia/Tokyo", latitude: nil, longitude: nil),
            network: NetworkInfo.preview.network,
            providerIdentifier: "metadata-test"
        )
    }
}

private final class MetadataTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 2_000)
    func now() -> Date { lock.withLock { date } }
    func advance(by seconds: TimeInterval) { lock.withLock { date = date.addingTimeInterval(seconds) } }
}

private actor SequenceMetadataProvider: GeoIPProvider {
    nonisolated let identifier = "metadata-test"
    private var results: [Result<GeoIPResult, NetworkFailure>]
    private(set) var callCount = 0
    init(results: [Result<GeoIPResult, NetworkFailure>]) { self.results = results }
    func lookup(ipAddress: String) async throws -> GeoIPResult {
        callCount += 1
        guard !results.isEmpty else { throw NetworkFailure.serviceUnavailable }
        return try results.removeFirst().get()
    }
}

private actor SuspendedMetadataProvider: GeoIPProvider {
    nonisolated let identifier = "suspended-metadata"
    private var started = false
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var resultContinuation: CheckedContinuation<GeoIPResult, Error>?
    func lookup(ipAddress: String) async throws -> GeoIPResult {
        started = true
        startedContinuation?.resume()
        startedContinuation = nil
        return try await withCheckedThrowingContinuation { resultContinuation = $0 }
    }
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }
    func finish(_ result: Result<GeoIPResult, NetworkFailure>) {
        switch result {
        case .success(let value): resultContinuation?.resume(returning: value)
        case .failure(let error): resultContinuation?.resume(throwing: error)
        }
        resultContinuation = nil
        started = false
    }
}

private struct MetadataPublicIPProvider: PublicIPProviding {
    func fetchAddresses() async throws -> IPAddressSet { NetworkInfo.preview.addresses }
}

private struct MetadataPrivacyProvider: PrivacyClassifying {
    func classify(ipAddress: String) async throws -> PrivacyClassification { .notDetected }
}

private actor RepeatingMetadataTestProbe: ExitAddressProbing {
    private let observation: ExitObservation
    private(set) var callCount = 0
    init(_ observation: ExitObservation) { self.observation = observation }
    func observeExit() async throws -> ExitObservation {
        callCount += 1
        return observation
    }
}
