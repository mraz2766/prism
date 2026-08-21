import XCTest
@testable import Prism

@MainActor
final class RealtimeExitMonitorTests: XCTestCase {
    func testExactObservationRefreshesWithoutSecondAddressLookup() async throws {
        let harness = makeHarness(cached: routedInfo(ip: "203.0.113.10", route: .proxy))
        let changed = observation(ip: "203.0.113.50", route: .proxy)
        let monitor = RealtimeExitMonitor(
            probe: SequenceObservationProbe(observations: [changed]),
            lookupService: harness.lookup
        )

        await monitor.pollNow()

        let publicIPCalls = await harness.publicIP.callCount
        let geoCalls = await harness.geo.callCount
        let status = await harness.lookup.snapshot()
        XCTAssertEqual(publicIPCalls, 0)
        XCTAssertEqual(geoCalls, 1)
        XCTAssertEqual(status.info?.addresses.ipv4, "203.0.113.50")
    }

    func testMetadataRefreshUsesExactUnchangedObservation() async throws {
        let cached = routedInfo(ip: "203.0.113.10", route: .proxy)
        let harness = makeHarness(cached: cached)
        let monitor = RealtimeExitMonitor(
            probe: SequenceObservationProbe(observations: [
                observation(ip: "203.0.113.10", route: .proxy)
            ]),
            lookupService: harness.lookup
        )

        await monitor.refreshNow(showLoading: true)

        let publicIPCalls = await harness.publicIP.callCount
        let geoCalls = await harness.geo.callCount
        let refreshedInfo = await harness.lookup.snapshot().info
        XCTAssertEqual(publicIPCalls, 0)
        XCTAssertEqual(geoCalls, 1)
        XCTAssertEqual(refreshedInfo?.addresses.ipv4, "203.0.113.10")
    }

    func testSingleDomesticFallbackDoesNotReplaceStableProxyExit() async throws {
        let original = routedInfo(ip: "203.0.113.10", route: .proxy)
        let harness = makeHarness(cached: original)
        let probe = SequenceObservationProbe(observations: [
            observation(ip: "198.51.100.30", route: .direct),
            observation(ip: "203.0.113.10", route: .proxy)
        ])
        let monitor = RealtimeExitMonitor(probe: probe, lookupService: harness.lookup)

        await monitor.pollNow()
        let pending = await harness.lookup.snapshot()
        await monitor.pollNow()
        let restored = await harness.lookup.snapshot()

        guard case .verifying(_, let candidate) = pending else {
            return XCTFail("Expected a pending verification state")
        }
        XCTAssertEqual(candidate, "198.51.100.30")
        XCTAssertEqual(restored.info?.addresses, original.addresses)
        XCTAssertEqual(restored.info?.routeMode, .proxy)
        let history = await harness.history.snapshot()
        let geoCalls = await harness.geo.callCount
        XCTAssertTrue(history.isEmpty)
        XCTAssertEqual(geoCalls, 0)
    }

    func testTwoDomesticObservationsConfirmOnceAndReuseSnapshotGeo() async throws {
        let harness = makeHarness(cached: routedInfo(ip: "203.0.113.10", route: .proxy))
        let domestic = observation(
            ip: "198.51.100.30",
            route: .direct,
            geo: geoResult(country: "CN", region: "Shanghai", city: "Shanghai")
        )
        let monitor = RealtimeExitMonitor(
            probe: SequenceObservationProbe(observations: [domestic, domestic]),
            lookupService: harness.lookup
        )

        await monitor.pollNow()
        await monitor.pollNow()

        let info = (await harness.lookup.snapshot()).info
        XCTAssertEqual(info?.location.countryCode, "CN")
        XCTAssertEqual(info?.location.city, "Shanghai")
        XCTAssertEqual(info?.routeMode, .direct)
        let geoCalls = await harness.geo.callCount
        let historyCount = await harness.history.snapshot().count
        XCTAssertEqual(geoCalls, 0)
        XCTAssertEqual(historyCount, 1)
    }

    func testConfirmedDirectRouteAcceptsSubsequentDirectIPImmediately() async throws {
        let harness = makeHarness(cached: routedInfo(ip: "198.51.100.30", route: .direct))
        let hangzhou = observation(
            ip: "198.51.100.31",
            route: .direct,
            geo: geoResult(country: "CN", region: "Zhejiang", city: "Hangzhou")
        )
        let monitor = RealtimeExitMonitor(
            probe: SequenceObservationProbe(observations: [hangzhou]),
            lookupService: harness.lookup
        )

        await monitor.pollNow()

        let info = (await harness.lookup.snapshot()).info
        XCTAssertEqual(info?.addresses.ipv4, "198.51.100.31")
        XCTAssertEqual(info?.location.city, "Hangzhou")
        let historyCount = await harness.history.snapshot().count
        XCTAssertEqual(historyCount, 1)
    }

    func testPausedMonitorDoesNotProbeUntilResumed() async throws {
        let harness = makeHarness(cached: routedInfo(ip: "203.0.113.10", route: .proxy))
        let probe = CountingObservationProbe(observation: observation(ip: "203.0.113.10", route: .proxy))
        let monitor = RealtimeExitMonitor(probe: probe, lookupService: harness.lookup)

        await monitor.pause()
        await monitor.pollNow()
        let pausedCalls = await probe.callCount
        XCTAssertEqual(pausedCalls, 0)
        await monitor.resume()
        await monitor.pollNow()
        let resumedCalls = await probe.callCount
        XCTAssertEqual(resumedCalls, 1)
    }

    func testStartedLoopPollsAndStopCancelsFutureProbes() async throws {
        let harness = makeHarness(cached: routedInfo(ip: "203.0.113.10", route: .proxy))
        let probe = CountingObservationProbe(observation: observation(ip: "203.0.113.10", route: .proxy))
        let monitor = RealtimeExitMonitor(
            probe: probe,
            lookupService: harness.lookup,
            interval: .milliseconds(10),
            burstInterval: .milliseconds(5),
            burstDuration: .milliseconds(30),
            isLowPowerModeEnabled: { false }
        )

        await monitor.start()
        try await Task.sleep(for: .milliseconds(45))
        await monitor.stop()
        let callsAtStop = await probe.callCount
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertGreaterThanOrEqual(callsAtStop, 2)
        let callsAfterStop = await probe.callCount
        XCTAssertEqual(callsAfterStop, callsAtStop)
    }

    func testLowPowerModeUsesSlowerStableInterval() async throws {
        let harness = makeHarness(cached: routedInfo(ip: "203.0.113.10", route: .proxy))
        let probe = CountingObservationProbe(observation: observation(ip: "203.0.113.10", route: .proxy))
        let monitor = RealtimeExitMonitor(
            probe: probe,
            lookupService: harness.lookup,
            interval: .milliseconds(5),
            lowPowerInterval: .milliseconds(60),
            burstInterval: .milliseconds(2),
            burstDuration: .zero,
            isLowPowerModeEnabled: { true }
        )

        await monitor.start()
        try await Task.sleep(for: .milliseconds(30))
        await monitor.stop()

        let callCount = await probe.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testConcurrentPollRequestsShareOneProbe() async throws {
        let harness = makeHarness(cached: routedInfo(ip: "203.0.113.10", route: .proxy))
        let probe = SlowCountingObservationProbe(
            observation: observation(ip: "203.0.113.10", route: .proxy)
        )
        let monitor = RealtimeExitMonitor(probe: probe, lookupService: harness.lookup)

        async let first: Void = monitor.pollNow()
        async let second: Void = monitor.pollNow()
        _ = await (first, second)

        let metrics = await probe.metrics
        XCTAssertEqual(metrics.callCount, 1)
        XCTAssertEqual(metrics.maximumConcurrentCalls, 1)
    }

    func testNetworkEnvironmentChangeDiscardsOldObservationAndForcesFreshConnection() async throws {
        let harness = makeHarness(cached: routedInfo(ip: "203.0.113.10", route: .proxy))
        let domestic = observation(
            ip: "198.51.100.30",
            route: .direct,
            geo: geoResult(country: "CN", region: "Shanghai", city: "Shanghai")
        )
        let probe = EnvironmentChangingObservationProbe(observations: [
            observation(ip: "203.0.113.99", route: .proxy),
            domestic,
            domestic
        ])
        let monitor = RealtimeExitMonitor(probe: probe, lookupService: harness.lookup)

        let oldPoll = Task { await monitor.pollNow() }
        try await Task.sleep(for: .milliseconds(5))
        await monitor.networkEnvironmentDidChange()
        await oldPoll.value
        await monitor.pollNow()

        let info = (await harness.lookup.snapshot()).info
        let metrics = await probe.metrics
        XCTAssertEqual(info?.addresses.ipv4, "198.51.100.30")
        XCTAssertEqual(info?.location.countryCode, "CN")
        XCTAssertEqual(metrics.callCount, 3)
        XCTAssertEqual(metrics.invalidationCount, 1)
    }

    func testSuccessfulStablePollRestoresOfflineStatusWhenRecoveryEventWasMissed() async {
        let original = routedInfo(ip: "203.0.113.10", route: .proxy)
        let harness = makeHarness(cached: original)
        await harness.lookup.markOffline()
        let monitor = RealtimeExitMonitor(
            probe: SequenceObservationProbe(observations: [
                observation(ip: "203.0.113.10", route: .proxy)
            ]),
            lookupService: harness.lookup
        )

        await monitor.pollNow()

        guard case .online(let info) = await harness.lookup.snapshot() else {
            return XCTFail("A successful observation must restore the online state")
        }
        XCTAssertEqual(info.addresses, original.addresses)
    }

    private func makeHarness(cached: NetworkInfo) -> MonitorHarness {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = NetworkInfoCache(directory: directory)
        cache.saveInfo(cached)
        let publicIP = CountingPublicIPProvider(addresses: cached.addresses)
        let geo = CountingGeoProvider()
        let history = NetworkHistoryStore(
            fileURL: directory.appendingPathComponent("history.json"),
            settlingDelay: .zero
        )
        let lookup = NetworkLookupService(
            publicIPProvider: publicIP,
            geoProvider: geo,
            privacyProvider: MonitorPrivacyProvider(),
            cache: cache,
            history: history
        )
        return MonitorHarness(lookup: lookup, publicIP: publicIP, geo: geo, history: history)
    }
}

private struct MonitorHarness {
    let lookup: NetworkLookupService
    let publicIP: CountingPublicIPProvider
    let geo: CountingGeoProvider
    let history: NetworkHistoryStore
}

func observation(
    ip: String,
    route: NetworkRouteMode,
    geo: GeoIPResult? = nil
) -> ExitObservation {
    ExitObservation(
        addresses: IPAddressSet(ipv4: ip, ipv6: nil),
        source: route == .direct ? .domesticFallback : .overseasIPv4,
        routeMode: route,
        preResolvedGeo: geo
    )
}

func routedInfo(ip: String, route: NetworkRouteMode) -> NetworkInfo {
    NetworkInfo(
        addresses: IPAddressSet(ipv4: ip, ipv6: nil),
        location: NetworkInfo.preview.location,
        network: NetworkInfo.preview.network,
        privacy: .notDetected,
        providerIdentifier: "fixture",
        routeMode: route,
        exitSource: route == .direct ? .domesticFallback : .overseasIPv4,
        checkedAt: .now
    )
}

private func geoResult(country: String, region: String, city: String) -> GeoIPResult {
    GeoIPResult(
        location: LocationInfo(
            countryCode: country,
            region: region,
            city: city,
            timezone: country == "CN" ? "Asia/Shanghai" : nil,
            latitude: nil,
            longitude: nil
        ),
        network: NetworkInfo.preview.network,
        providerIdentifier: "fixture-geo"
    )
}

private actor SequenceObservationProbe: ExitAddressProbing {
    private var observations: [ExitObservation]

    init(observations: [ExitObservation]) {
        self.observations = observations
    }

    func observeExit() async throws -> ExitObservation {
        guard !observations.isEmpty else { throw NetworkFailure.serviceUnavailable }
        return observations.removeFirst()
    }
}

private actor CountingObservationProbe: ExitAddressProbing {
    let observation: ExitObservation
    private(set) var callCount = 0

    init(observation: ExitObservation) {
        self.observation = observation
    }

    func observeExit() async throws -> ExitObservation {
        callCount += 1
        return observation
    }
}

private actor SlowCountingObservationProbe: ExitAddressProbing {
    let observation: ExitObservation
    private var callCount = 0
    private var concurrentCalls = 0
    private var maximumConcurrentCalls = 0

    init(observation: ExitObservation) {
        self.observation = observation
    }

    var metrics: (callCount: Int, maximumConcurrentCalls: Int) {
        (callCount, maximumConcurrentCalls)
    }

    func observeExit() async throws -> ExitObservation {
        callCount += 1
        concurrentCalls += 1
        maximumConcurrentCalls = max(maximumConcurrentCalls, concurrentCalls)
        defer { concurrentCalls -= 1 }
        try await Task.sleep(for: .milliseconds(30))
        return observation
    }
}

private actor EnvironmentChangingObservationProbe: ExitAddressProbing {
    private var observations: [ExitObservation]
    private var callCount = 0
    private var invalidationCount = 0

    init(observations: [ExitObservation]) {
        self.observations = observations
    }

    var metrics: (callCount: Int, invalidationCount: Int) {
        (callCount, invalidationCount)
    }

    func observeExit() async throws -> ExitObservation {
        let index = callCount
        callCount += 1
        guard !observations.isEmpty else { throw NetworkFailure.serviceUnavailable }
        let observation = observations.removeFirst()
        if index == 0 {
            try? await Task.sleep(for: .milliseconds(30))
        }
        return observation
    }

    func invalidateConnections() async {
        invalidationCount += 1
    }
}

private actor CountingPublicIPProvider: PublicIPProviding {
    let addresses: IPAddressSet
    private(set) var callCount = 0

    init(addresses: IPAddressSet) {
        self.addresses = addresses
    }

    func fetchAddresses() async throws -> IPAddressSet {
        callCount += 1
        return addresses
    }
}

private actor CountingGeoProvider: GeoIPProvider {
    nonisolated let identifier = "monitor-geo"
    private(set) var callCount = 0

    func lookup(ipAddress: String) async throws -> GeoIPResult {
        callCount += 1
        return geoResult(country: "SG", region: "Singapore", city: "Singapore")
    }
}

private actor MonitorPrivacyProvider: PrivacyClassifying {
    func classify(ipAddress: String) async throws -> PrivacyClassification { .notDetected }
}
