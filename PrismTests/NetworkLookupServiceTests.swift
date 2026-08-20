import XCTest
@testable import Prism

final class NetworkLookupServiceTests: XCTestCase {
    func testRefreshesGeoEveryTimeButReusesPrivacyAndCoalescesConcurrentRefreshes() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let publicIP = CountingPublicIPProvider(delay: .milliseconds(50))
        let geo = CountingGeoProvider()
        let privacy = CountingPrivacyProvider()
        let service = NetworkLookupService(
            publicIPProvider: publicIP,
            geoProvider: geo,
            privacyProvider: privacy,
            cache: NetworkInfoCache(directory: directory),
            history: NetworkHistoryStore(
                fileURL: directory.appendingPathComponent("history.json"),
                settlingDelay: .zero
            )
        )

        async let first = service.refresh()
        async let second = service.refresh()
        _ = await (first, second)
        _ = await service.refresh()

        let publicIPCalls = await publicIP.callCount
        let geoCalls = await geo.callCount
        let privacyCalls = await privacy.callCount
        XCTAssertEqual(publicIPCalls, 2)
        XCTAssertEqual(geoCalls, 2)
        XCTAssertEqual(privacyCalls, 1)
    }

    func testStartupHidesCachedInformationUntilARefreshFails() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = NetworkInfoCache(directory: directory)
        cache.saveInfo(.preview)
        let service = NetworkLookupService(
            publicIPProvider: FailingPublicIPProvider(),
            geoProvider: CountingGeoProvider(),
            privacyProvider: CountingPrivacyProvider(),
            cache: cache,
            history: NetworkHistoryStore(
                fileURL: directory.appendingPathComponent("history.json"),
                settlingDelay: .zero
            )
        )

        let initial = await service.snapshot()
        let cachedForComparison = await service.comparisonInfo()
        XCTAssertEqual(initial, .idle, "Startup must not flash a previous country")
        XCTAssertEqual(cachedForComparison?.addresses, NetworkInfo.preview.addresses)

        let refreshed = await service.refresh(showLoading: true)
        guard case .stale(let retained, let reason) = refreshed else {
            return XCTFail("A failed update should retain cached information")
        }
        XCTAssertEqual(retained.addresses, NetworkInfo.preview.addresses)
        XCTAssertEqual(reason, .serviceUnavailable)
    }

    func testReturningToPreviouslySeenAddressRefreshesGeoButNotPrivacy() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let first = IPAddressSet(ipv4: "198.51.100.10", ipv6: nil)
        let second = IPAddressSet(ipv4: "198.51.100.11", ipv6: nil)
        let publicIP = CyclingPublicIPProvider(addresses: [first, second, first])
        let geo = CountingGeoProvider()
        let privacy = CountingPrivacyProvider()
        let service = NetworkLookupService(
            publicIPProvider: publicIP,
            geoProvider: geo,
            privacyProvider: privacy,
            cache: NetworkInfoCache(directory: directory),
            history: NetworkHistoryStore(
                fileURL: directory.appendingPathComponent("history.json"),
                settlingDelay: .zero
            )
        )

        _ = await service.refresh()
        _ = await service.refresh()
        _ = await service.refresh()

        let geoCallCount = await geo.callCount
        let privacyCallCount = await privacy.callCount
        XCTAssertEqual(geoCallCount, 3, "Every full refresh must obtain fresh city data")
        XCTAssertEqual(privacyCallCount, 2, "Privacy results remain cached once per IP")
    }

    func testHardDeadlineStopsAStalledRefresh() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let service = makeService(
            directory: directory,
            publicIPProvider: DelayedPublicIPProvider(delay: .seconds(5)),
            hardTimeout: .milliseconds(20)
        )

        let status = await service.refresh()

        XCTAssertEqual(status, .failed(.timeout))
    }

    func testCallerCancellationCancelsOwnedRefresh() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let service = makeService(
            directory: directory,
            publicIPProvider: DelayedPublicIPProvider(delay: .seconds(5))
        )
        let refresh = Task { await service.refresh() }
        try await Task.sleep(for: .milliseconds(20))

        refresh.cancel()
        let status = await refresh.value

        XCTAssertEqual(status, .failed(.cancelled))
    }

    private func makeService(
        directory: URL,
        publicIPProvider: any PublicIPProviding,
        hardTimeout: Duration = .seconds(15)
    ) -> NetworkLookupService {
        NetworkLookupService(
            publicIPProvider: publicIPProvider,
            geoProvider: CountingGeoProvider(),
            privacyProvider: CountingPrivacyProvider(),
            cache: NetworkInfoCache(directory: directory),
            history: NetworkHistoryStore(
                fileURL: directory.appendingPathComponent("history.json"),
                settlingDelay: .zero
            ),
            hardTimeout: hardTimeout
        )
    }
}

private actor CountingPublicIPProvider: PublicIPProviding {
    private(set) var callCount = 0
    let delay: Duration

    init(delay: Duration) {
        self.delay = delay
    }

    func fetchAddresses() async throws -> IPAddressSet {
        callCount += 1
        try await Task.sleep(for: delay)
        return NetworkInfo.preview.addresses
    }
}

private actor CountingGeoProvider: GeoIPProvider {
    nonisolated let identifier = "counting-geo"
    private(set) var callCount = 0

    func lookup(ipAddress: String) async throws -> GeoIPResult {
        callCount += 1
        return GeoIPResult(
            location: NetworkInfo.preview.location,
            network: NetworkInfo.preview.network,
            providerIdentifier: identifier
        )
    }
}

private actor CountingPrivacyProvider: PrivacyClassifying {
    private(set) var callCount = 0

    func classify(ipAddress: String) async throws -> PrivacyClassification {
        callCount += 1
        return .notDetected
    }
}

private actor CyclingPublicIPProvider: PublicIPProviding {
    private var addresses: [IPAddressSet]

    init(addresses: [IPAddressSet]) {
        self.addresses = addresses
    }

    func fetchAddresses() async throws -> IPAddressSet {
        guard !addresses.isEmpty else { throw NetworkFailure.serviceUnavailable }
        return addresses.removeFirst()
    }
}

private struct FailingPublicIPProvider: PublicIPProviding {
    func fetchAddresses() async throws -> IPAddressSet {
        throw NetworkFailure.serviceUnavailable
    }
}

private struct DelayedPublicIPProvider: PublicIPProviding {
    let delay: Duration

    func fetchAddresses() async throws -> IPAddressSet {
        try await Task.sleep(for: delay)
        return NetworkInfo.preview.addresses
    }
}
