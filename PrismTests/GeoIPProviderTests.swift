import XCTest
@testable import Prism

final class GeoIPProviderTests: XCTestCase {
    func testIPWhoIsMapsWireResponse() async throws {
        let base = try XCTUnwrap(URL(string: "https://example.test/"))
        let endpoint = base.appendingPathComponent("203.0.113.10")
        let client = RoutingHTTPClient(responses: [
            endpoint.absoluteString: response(#"""
            {
              "success": true,
              "country_code": "JP",
              "region": "Tokyo",
              "city": "Tokyo",
              "latitude": 35.67,
              "longitude": 139.65,
              "connection": {"asn": 13335, "org": "Example Org", "isp": "Example ISP"},
              "timezone": {"id": "Asia/Tokyo"}
            }
            """#)
        ])
        let provider = IPWhoIsGeoProvider(client: client, baseURL: base)

        let result = try await provider.lookup(ipAddress: "203.0.113.10")

        XCTAssertEqual(result.location.countryCode, "JP")
        XCTAssertEqual(result.location.city, "Tokyo")
        XCTAssertEqual(result.network.asn, 13335)
        XCTAssertEqual(result.network.isp, "Example ISP")
    }

    func testFallbackUsesSecondProvider() async throws {
        let expected = GeoIPResult(
            location: NetworkInfo.preview.location,
            network: NetworkInfo.preview.network,
            providerIdentifier: "secondary"
        )
        let provider = FallbackGeoIPProvider(providers: [
            StubGeoProvider(identifier: "primary", result: .failure(.serviceUnavailable)),
            StubGeoProvider(identifier: "secondary", result: .success(expected))
        ])

        let result = try await provider.lookup(ipAddress: "203.0.113.1")

        XCTAssertEqual(result, expected)
    }

    func testProviderHealthOpensCircuitAfterRepeatedFailuresAndSuccessResetsIt() async {
        let health = ProviderHealthRegistry(failureThreshold: 2, cooldown: 30)
        await health.recordFailure("primary", failure: .timeout, latency: .milliseconds(800))
        await health.recordFailure("primary", failure: .timeout, latency: .milliseconds(900))

        let canAttemptWhileOpen = await health.canAttempt("primary")
        XCTAssertFalse(canAttemptWhileOpen)
        let openSnapshot = await health.snapshots(order: ["primary"])
        XCTAssertEqual(openSnapshot.first?.consecutiveFailures, 2)
        XCTAssertEqual(openSnapshot.first?.lastLatencyMilliseconds, 900)
        XCTAssertEqual(openSnapshot.first?.isCircuitOpen, true)

        await health.recordSuccess("primary", latency: .milliseconds(120))

        let canAttemptAfterRecovery = await health.canAttempt("primary")
        XCTAssertTrue(canAttemptAfterRecovery)
        let recoveredSnapshot = await health.snapshots(order: ["primary"])
        XCTAssertEqual(recoveredSnapshot.first?.consecutiveFailures, 0)
        XCTAssertEqual(recoveredSnapshot.first?.lastLatencyMilliseconds, 120)
    }

    func testFallbackSkipsProviderWhileItsCircuitIsOpen() async throws {
        let health = ProviderHealthRegistry(failureThreshold: 1, cooldown: 30)
        await health.recordFailure("primary", failure: .timeout, latency: .seconds(1))
        let expected = GeoIPResult(
            location: NetworkInfo.preview.location,
            network: NetworkInfo.preview.network,
            providerIdentifier: "secondary"
        )
        let provider = FallbackGeoIPProvider(
            providers: [
                StubGeoProvider(identifier: "primary", result: .failure(.other)),
                StubGeoProvider(identifier: "secondary", result: .success(expected))
            ],
            health: health
        )

        let result = try await provider.lookup(ipAddress: "203.0.113.1")

        XCTAssertEqual(result, expected)
    }

    func testIPGuideMapsWireResponse() async throws {
        let base = try XCTUnwrap(URL(string: "https://example.test/"))
        let endpoint = base.appendingPathComponent("8.8.8.8")
        let client = RoutingHTTPClient(responses: [
            endpoint.absoluteString: response(#"""
            {
              "network": {
                "autonomous_system": {"asn": 15169, "organization": "Google LLC"}
              },
              "location": {
                "city": null,
                "country": "United States",
                "timezone": "America/Los_Angeles",
                "latitude": 37.4,
                "longitude": -122.1
              }
            }
            """#)
        ])
        let provider = IPGuideGeoProvider(client: client, baseURL: base)

        let result = try await provider.lookup(ipAddress: "8.8.8.8")

        XCTAssertEqual(result.location.countryCode, "US")
        XCTAssertNil(result.location.city)
        XCTAssertEqual(result.network.asn, 15169)
        XCTAssertEqual(result.network.organization, "Google LLC")
    }

    func testGeoProvidersExplicitlyDisableResponseCaching() async throws {
        let base = try XCTUnwrap(URL(string: "https://example.test/"))
        let whoClient = RecordingGeoHTTPClient(response: response(#"""
        {"success":true,"country_code":"CN","region":"Shanghai","city":"Shanghai"}
        """#))
        let guideClient = RecordingGeoHTTPClient(response: response(#"""
        {
          "network":{"autonomous_system":{"asn":4812,"organization":"China Telecom"}},
          "location":{"city":"Shanghai","country":"China","timezone":"Asia/Shanghai","latitude":31.23,"longitude":121.47}
        }
        """#))

        _ = try await IPWhoIsGeoProvider(client: whoClient, baseURL: base)
            .lookup(ipAddress: "198.51.100.20")
        _ = try await IPGuideGeoProvider(client: guideClient, baseURL: base)
            .lookup(ipAddress: "198.51.100.20")

        for request in [await whoClient.lastRequest, await guideClient.lastRequest] {
            let request = try XCTUnwrap(request)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store, no-cache")
        }
    }

    func testIPIPMapsDomesticChineseLocationToEnglishCity() async throws {
        let endpoint = try XCTUnwrap(URL(string: "https://example.test/domestic"))
        let client = RoutingHTTPClient(responses: [
            endpoint.absoluteString: response(#"""
            {"ret":"ok","data":{"ip":"180.173.166.20","location":["中国","上海市","上海市","","中国电信"]}}
            """#)
        ])
        let provider = IPIPGeoProvider(client: client, endpoint: endpoint)

        let result = try await provider.lookup(ipAddress: "180.173.166.20")

        XCTAssertEqual(result.location.countryCode, "CN")
        XCTAssertEqual(result.location.region, "Shanghai")
        XCTAssertEqual(result.location.city, "Shanghai")
        XCTAssertEqual(result.network.isp, "中国电信")
        XCTAssertEqual(result.providerIdentifier, "ipip.net")
    }

    func testIPIPRejectsLocationFromAContradictingSplitRouteAddress() async throws {
        let endpoint = try XCTUnwrap(URL(string: "https://example.test/domestic"))
        let client = RoutingHTTPClient(responses: [
            endpoint.absoluteString: response(#"{"ret":"ok","data":{"ip":"180.173.166.20","location":["中国","上海","上海","","电信"]}}"#)
        ])
        let provider = IPIPGeoProvider(client: client, endpoint: endpoint)

        do {
            _ = try await provider.lookup(ipAddress: "13.193.241.118")
            XCTFail("A domestic direct-route location must not replace a VPN exit")
        } catch let failure as NetworkFailure {
            XCTAssertEqual(failure, .invalidResponse)
        }
    }

    func testChineseAdministrativeNamesTransliterateWithoutSuffixes() {
        XCTAssertEqual(
            IPIPGeoProvider.englishAdministrativeName("浙江省", suffixes: ["省", "市"]),
            "Zhejiang"
        )
        XCTAssertEqual(
            IPIPGeoProvider.englishAdministrativeName("杭州市", suffixes: ["自治州", "市"]),
            "Hangzhou"
        )
        XCTAssertEqual(
            IPIPGeoProvider.englishAdministrativeName("宁波市", suffixes: ["市"]),
            "Ningbo"
        )
    }
}

private actor RecordingGeoHTTPClient: HTTPClient {
    private let response: HTTPResponse
    private(set) var lastRequest: URLRequest?

    init(response: HTTPResponse) {
        self.response = response
    }

    func data(for request: URLRequest) async throws -> HTTPResponse {
        lastRequest = request
        return response
    }
}
