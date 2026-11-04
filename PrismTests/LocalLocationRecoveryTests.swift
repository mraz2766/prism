import XCTest
@testable import Prism

final class LocalLocationRecoveryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let japaneseIP = "3.113.21.153"
    private let domesticIP = "180.173.166.20"

    func testJapaneseHistorySurvivesDomesticSnapshotAndReturnWithTimeout() async {
        let recordedAt = now.addingTimeInterval(-3_600)
        let japan = info(ip: japaneseIP, country: "JP", city: "Tokyo", at: recordedAt)
        let historical = NetworkHistoryEntry(recordedAt: recordedAt, info: japan)
        let harness = makeHarness(
            geo: FailingLocalRecoveryGeo(),
            country: StubLocalCountry(code: "US"),
            historyEntries: [historical]
        )
        let mainland = observation(ip: domesticIP, country: "CN", city: "Shanghai")
        _ = await harness.service.refresh(observation: mainland)

        let status = await harness.service.refresh(observation: observation(ip: japaneseIP))

        guard case .locationUnavailable(let restored, .timeout) = status else {
            return XCTFail("Online enrichment failure should retain the exact IP's known location")
        }
        XCTAssertEqual(restored.addresses.ipv4, japaneseIP)
        XCTAssertEqual(restored.location.countryCode, "JP")
        XCTAssertEqual(restored.location.city, "Tokyo")
        XCTAssertEqual(restored.locationSource, .history)
        XCTAssertEqual(restored.locationCheckedAt, recordedAt)
        XCTAssertEqual(harness.cache.loadLocations()[japaneseIP]?.location.countryCode, "JP")
        XCTAssertEqual(harness.cache.loadLocations()[domesticIP]?.location.countryCode, "CN")
    }

    func testOfflineCountryIsVisibleBeforeOnlineLookupAndRemainsNormalAfterTimeout() async {
        let geo = SuspendedLocalRecoveryGeo()
        let harness = makeHarness(geo: geo, country: StubLocalCountry(code: "JP"))
        let observed = observation(ip: japaneseIP)
        let refresh = Task { await harness.service.refresh(observation: observed) }
        await geo.waitUntilStarted()
        let pending = await harness.service.snapshot()
        guard case .locating(let current) = pending else {
            await geo.fail()
            _ = await refresh.value
            return XCTFail("The IP and offline country should be published before the network request finishes")
        }
        XCTAssertEqual(current.addresses, observed.addresses)
        XCTAssertEqual(current.location.countryCode, "JP")
        XCTAssertNil(current.location.city)
        XCTAssertEqual(current.locationSource, .offline)
        XCTAssertNil(current.locationCheckedAt)
        XCTAssertEqual(pending.shortLabel, NetworkStatus.online(current).shortLabel)
        XCTAssertEqual(pending.symbolName, "checkmark.circle.fill")
        XCTAssertFalse(pending.isRefreshing)

        await geo.fail()
        let failed = await refresh.value
        guard case .locationUnavailable(let retained, .timeout) = failed else {
            return XCTFail("Expected a recoverable enrichment failure")
        }
        XCTAssertEqual(retained.location.countryCode, "JP")
        XCTAssertEqual(retained.locationSource, .offline)
        XCTAssertNil(retained.locationCheckedAt)
        XCTAssertEqual(failed.shortLabel, NetworkStatus.online(retained).shortLabel)
        XCTAssertEqual(failed.symbolName, "checkmark.circle.fill")
        XCTAssertTrue(harness.cache.loadLocations().isEmpty, "Offline estimates must not become online success records")
    }

    func testNoOfflineCoverageStillShowsConfirmedIPNormally() async {
        let harness = makeHarness(geo: FailingLocalRecoveryGeo(), country: StubLocalCountry(code: nil))
        let observed = observation(ip: "8.8.4.4")

        let status = await harness.service.refresh(observation: observed)

        guard case .locationUnavailable(let current, .timeout) = status else {
            return XCTFail("Missing metadata must not discard a confirmed IP")
        }
        XCTAssertEqual(current.addresses, observed.addresses)
        XCTAssertFalse(current.hasLocation)
        XCTAssertEqual(current.locationSource, .unknown)
        XCTAssertNil(current.locationCheckedAt)
        XCTAssertEqual(status.shortLabel, NetworkStatus.online(current).shortLabel)
        XCTAssertEqual(status.symbolName, "checkmark.circle.fill")
    }

    func testSuccessfulIPCacheSurvivesRestartWithAnotherExitAsLatestSnapshot() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = makeHarness(geo: FailingLocalRecoveryGeo(), country: StubLocalCountry(code: nil), directory: directory)
        let japanese = observation(ip: japaneseIP, country: "JP", city: "Tokyo")
        _ = await first.service.refresh(observation: japanese)
        _ = await first.service.refresh(observation: observation(ip: domesticIP, country: "CN", city: "Shanghai"))
        XCTAssertEqual(first.cache.loadInfo()?.addresses.ipv4, domesticIP)

        let restarted = makeHarness(geo: FailingLocalRecoveryGeo(), country: StubLocalCountry(code: "US"), directory: directory)
        let status = await restarted.service.refresh(observation: observation(ip: japaneseIP))

        XCTAssertEqual(status.info?.addresses.ipv4, japaneseIP)
        XCTAssertEqual(status.info?.location.countryCode, "JP")
        XCTAssertEqual(status.info?.location.city, "Tokyo")
        XCTAssertEqual(status.info?.locationSource, .history)
        XCTAssertEqual(status.info?.locationCheckedAt, now)
    }

    func testDualStackHistoryDoesNotAssignIPv4LocationToUnlookedUpIPv6() async {
        let ipv6 = "2406:da14:c77:8e00:ee06:4169:52c7:d4e0"
        let historicalInfo = NetworkInfo(
            addresses: IPAddressSet(ipv4: japaneseIP, ipv6: ipv6),
            location: location(country: "JP", city: "Tokyo"),
            network: .unavailable,
            privacy: .unavailable,
            providerIdentifier: "fixture",
            checkedAt: now.addingTimeInterval(-60)
        )
        let entry = NetworkHistoryEntry(recordedAt: now.addingTimeInterval(-60), info: historicalInfo)
        let harness = makeHarness(
            geo: FailingLocalRecoveryGeo(), country: StubLocalCountry(code: nil), historyEntries: [entry]
        )
        let ipv6Only = ExitObservation(
            addresses: IPAddressSet(ipv4: nil, ipv6: ipv6),
            source: .overseasIPv6, routeMode: .unknown, observedAt: now
        )

        let status = await harness.service.refresh(observation: ipv6Only)

        XCTAssertEqual(status.info?.addresses.ipv6, ipv6)
        XCTAssertEqual(status.info?.hasLocation, false)
        XCTAssertEqual(status.info?.locationSource, .unknown)
        XCTAssertEqual(harness.cache.loadLocations()[japaneseIP]?.location.countryCode, "JP")
        XCTAssertNil(harness.cache.loadLocations()[IPAddressKey.normalized(ipv6)!])
    }

    func testOfflineCountryTakesPriorityOverHistoryOlderThanThirtyDays() async {
        let oldDate = now.addingTimeInterval(-31 * 24 * 60 * 60)
        let old = info(ip: japaneseIP, country: "US", city: "New York", at: oldDate)
        let harness = makeHarness(
            geo: FailingLocalRecoveryGeo(),
            country: StubLocalCountry(code: "JP"),
            historyEntries: [NetworkHistoryEntry(recordedAt: oldDate, info: old)]
        )

        let status = await harness.service.refresh(observation: observation(ip: japaneseIP))

        XCTAssertEqual(status.info?.location.countryCode, "JP")
        XCTAssertNil(status.info?.location.city)
        XCTAssertEqual(status.info?.locationSource, .offline)
        XCTAssertNil(status.info?.locationCheckedAt)
        XCTAssertEqual(harness.cache.loadLocations()[japaneseIP]?.location.countryCode, "US", "A fallback estimate must not overwrite the retained historical fact")
    }

    private func makeHarness(
        geo: any GeoIPProvider,
        country: any CountryLookingUp,
        directory: URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
        historyEntries: [NetworkHistoryEntry]? = nil
    ) -> LocalRecoveryHarness {
        let cache = NetworkInfoCache(directory: directory)
        let fixedNow = now
        return LocalRecoveryHarness(
            service: NetworkLookupService(
                publicIPProvider: UnusedLocalRecoveryPublicIP(),
                geoProvider: geo,
                privacyProvider: LocalRecoveryPrivacy(),
                cache: cache,
                history: NetworkHistoryStore(
                    fileURL: directory.appendingPathComponent("history.json"),
                    settlingDelay: .zero,
                    initialEntries: historyEntries
                ),
                countryLookup: country,
                now: { fixedNow }
            ),
            cache: cache
        )
    }

    private func observation(ip: String, country: String? = nil, city: String? = nil) -> ExitObservation {
        let geo = country.map {
            GeoIPResult(location: location(country: $0, city: city), network: .unavailable, providerIdentifier: "fixture")
        }
        return ExitObservation(
            addresses: IPAddressSet(ipv4: ip, ipv6: nil),
            source: ip == domesticIP ? .domesticFallback : .overseasIPv4,
            routeMode: .unknown,
            observedAt: now,
            preResolvedGeo: geo
        )
    }

    private func info(ip: String, country: String, city: String, at date: Date) -> NetworkInfo {
        NetworkInfo(
            addresses: IPAddressSet(ipv4: ip, ipv6: nil),
            location: location(country: country, city: city),
            network: .unavailable,
            privacy: .unavailable,
            providerIdentifier: "fixture",
            checkedAt: date
        )
    }

    private func location(country: String, city: String?) -> LocationInfo {
        LocationInfo(countryCode: country, region: nil, city: city, timezone: nil, latitude: nil, longitude: nil)
    }
}

private struct LocalRecoveryHarness {
    let service: NetworkLookupService
    let cache: NetworkInfoCache
}

private struct StubLocalCountry: CountryLookingUp {
    let code: String?
    func countryCode(for ipAddress: String) -> String? { code }
}

private struct FailingLocalRecoveryGeo: GeoIPProvider {
    let identifier = "failing-local-recovery"
    func lookup(ipAddress: String) async throws -> GeoIPResult { throw NetworkFailure.timeout }
}

private actor SuspendedLocalRecoveryGeo: GeoIPProvider {
    nonisolated let identifier = "suspended-local-recovery"
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

    func fail() {
        resultContinuation?.resume(throwing: NetworkFailure.timeout)
        resultContinuation = nil
    }
}

private struct UnusedLocalRecoveryPublicIP: PublicIPProviding {
    func fetchAddresses() async throws -> IPAddressSet { throw NetworkFailure.other }
}

private struct LocalRecoveryPrivacy: PrivacyClassifying {
    func classify(ipAddress: String) async throws -> PrivacyClassification { .notDetected }
}
