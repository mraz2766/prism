import XCTest
@testable import Prism

final class ExitFailoverTests: XCTestCase {
    func testJapanFallsBackToChinaAndRecoversWithoutOnlineGeoIP() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = FailoverHTTPClient()
        let geo = UnavailableFailoverGeo()
        let history = NetworkHistoryStore(fileURL: directory.appendingPathComponent("history.json"), settlingDelay: .zero)
        let service = NetworkLookupService(
            publicIPProvider: UnusedFailoverPublicIP(), geoProvider: geo,
            privacyProvider: FailoverPrivacy(), cache: NetworkInfoCache(directory: directory), history: history
        )
        let monitor = RealtimeExitMonitor(
            probe: IPifyExitAddressProbe(
                client: client,
                ipv4Endpoint: URL(string: "https://probe.test/v4")!,
                ipv6Endpoint: URL(string: "https://probe.test/v6")!,
                domesticEndpoint: URL(string: "https://probe.test/domestic")!
            ),
            lookupService: service
        )

        await monitor.pollNow()
        await monitor.pollNow()
        let japan = await service.snapshot()
        XCTAssertEqual(japan.info?.location.countryCode, "JP")
        XCTAssertEqual(japan.info?.locationSource, .offline)
        XCTAssertEqual(japan.info?.exitSource, .overseasIPv4)

        await client.setOverseasAvailable(false)
        await monitor.pollNow()
        let confirmingDomestic = await service.snapshot()
        guard case .verifying = confirmingDomestic else { return XCTFail("Require two fallback observations") }
        XCTAssertEqual(confirmingDomestic.info?.location.countryCode, "JP")
        await monitor.pollNow()
        let china = await service.snapshot()
        XCTAssertEqual(china.info?.addresses.ipv4, "180.173.166.20")
        XCTAssertEqual(china.info?.location.countryCode, "CN")
        XCTAssertEqual(china.info?.location.city, "Shanghai")
        XCTAssertEqual(china.info?.exitSource, .domesticFallback)
        XCTAssertEqual(china.shortLabel, String(localized: "Domestic available"))
        XCTAssertFalse(china.isRefreshing)
        let fallbackGeoCalls = await geo.callCount
        XCTAssertEqual(fallbackGeoCalls, 1, "Domestic response already contains its own location")

        await client.setOverseasAvailable(true)
        await monitor.pollNow()
        let confirmingRecovery = await service.snapshot()
        guard case .verifying = confirmingRecovery else { return XCTFail("Require two recovery observations") }
        XCTAssertEqual(confirmingRecovery.info?.location.countryCode, "CN")
        await monitor.pollNow()
        let recovered = await service.snapshot()
        XCTAssertEqual(recovered.info?.addresses.ipv4, "3.113.21.153")
        XCTAssertEqual(recovered.info?.location.countryCode, "JP")
        XCTAssertEqual(recovered.info?.locationSource, .offline)
        XCTAssertEqual(recovered.info?.exitSource, .overseasIPv4)
        XCTAssertEqual(recovered.shortLabel, String(localized: "Online"))
        XCTAssertFalse(recovered.isRefreshing, "Online metadata failure must not block recovery")
        let entries = await history.snapshot()
        XCTAssertEqual(entries.map(\.countryCode), ["JP", "CN", "JP"])
    }

    func testHistoryRecordsPathChangeEvenWhenIPAddressIsUnchanged() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = NetworkHistoryStore(fileURL: directory.appendingPathComponent("history.json"), settlingDelay: .zero)
        for source in [ExitSource.overseasIPv4, .domesticFallback, .overseasIPv4] {
            let info = NetworkInfo(
                addresses: NetworkInfo.preview.addresses,
                location: NetworkInfo.preview.location, network: .unavailable,
                privacy: .unavailable, providerIdentifier: "fixture", exitSource: source, checkedAt: .now
            )
            _ = await history.recordIfChanged(info)
        }
        let entries = await history.snapshot()
        XCTAssertEqual(entries.map(\.exitSource), [.overseasIPv4, .domesticFallback, .overseasIPv4])
    }
}

private actor FailoverHTTPClient: HTTPClient {
    private var overseasAvailable = true

    func setOverseasAvailable(_ available: Bool) { overseasAvailable = available }

    func data(for request: URLRequest) async throws -> HTTPResponse {
        switch request.url?.path {
        case "/v4":
            guard overseasAvailable else { throw NetworkFailure.timeout }
            return HTTPResponse(data: Data(#"{"ip":"3.113.21.153"}"#.utf8), statusCode: 200)
        case "/v6":
            throw NetworkFailure.timeout
        case "/domestic":
            return HTTPResponse(
                data: Data(#"{"ret":"ok","data":{"ip":"180.173.166.20","location":["中国","上海","上海","","电信"]}}"#.utf8),
                statusCode: 200
            )
        default: throw NetworkFailure.invalidResponse
        }
    }
}

private actor UnavailableFailoverGeo: GeoIPProvider {
    nonisolated let identifier = "unavailable"
    private(set) var callCount = 0
    func lookup(ipAddress: String) async throws -> GeoIPResult {
        callCount += 1
        throw NetworkFailure.timeout
    }
}

private struct UnusedFailoverPublicIP: PublicIPProviding {
    func fetchAddresses() async throws -> IPAddressSet {
        XCTFail("Use the exact probe observation instead of probing the address twice")
        throw NetworkFailure.serviceUnavailable
    }
}

private struct FailoverPrivacy: PrivacyClassifying {
    func classify(ipAddress: String) async throws -> PrivacyClassification { .unavailable }
}
