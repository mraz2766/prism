import XCTest
@testable import Prism

final class ExitAddressProbeTests: XCTestCase {
    func testPrefersValidIPv4Address() async throws {
        let ipv4 = try XCTUnwrap(URL(string: "https://example.test/v4"))
        let ipv6 = try XCTUnwrap(URL(string: "https://example.test/v6"))
        let client = RoutingHTTPClient(responses: [
            ipv4.absoluteString: response(#"{"ip":"203.0.113.40"}"#),
            ipv6.absoluteString: response(#"{"ip":"2001:db8::40"}"#)
        ])
        let probe = IPifyExitAddressProbe(client: client, ipv4Endpoint: ipv4, ipv6Endpoint: ipv6)

        let observation = try await probe.observeExit()

        XCTAssertEqual(observation.primaryAddress, "203.0.113.40")
        XCTAssertEqual(observation.addresses.ipv4, "203.0.113.40")
        XCTAssertEqual(observation.addresses.ipv6, "2001:db8::40")
    }

    func testFallsBackToIPv6WhenIPv4ResponseIsInvalid() async throws {
        let ipv4 = try XCTUnwrap(URL(string: "https://example.test/v4"))
        let ipv6 = try XCTUnwrap(URL(string: "https://example.test/v6"))
        let client = RoutingHTTPClient(responses: [
            ipv4.absoluteString: response(#"{"ip":"not-an-address"}"#),
            ipv6.absoluteString: response(#"{"ip":"2001:db8::41"}"#)
        ])
        let probe = IPifyExitAddressProbe(client: client, ipv4Endpoint: ipv4, ipv6Endpoint: ipv6)

        let address = try await probe.fetchPrimaryAddress()

        XCTAssertEqual(address, "2001:db8::41")
    }

    func testCancellationDoesNotStartFallbackRequest() async throws {
        let ipv4 = try XCTUnwrap(URL(string: "https://example.test/v4"))
        let ipv6 = try XCTUnwrap(URL(string: "https://example.test/v6"))
        let client = SlowProbeHTTPClient()
        let probe = IPifyExitAddressProbe(client: client, ipv4Endpoint: ipv4, ipv6Endpoint: ipv6)
        let task = Task { try await probe.fetchPrimaryAddress() }
        try await Task.sleep(for: .milliseconds(20))

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("A cancelled probe must not succeed")
        } catch is CancellationError {
            // Expected.
        }
        let calls = await client.callCount
        XCTAssertEqual(calls, 2)
    }

    func testInvalidResponsesFromBothFamiliesFail() async throws {
        let ipv4 = try XCTUnwrap(URL(string: "https://example.test/v4"))
        let ipv6 = try XCTUnwrap(URL(string: "https://example.test/v6"))
        let domestic = try XCTUnwrap(URL(string: "https://example.test/domestic"))
        let client = RoutingHTTPClient(responses: [
            ipv4.absoluteString: response(#"{"ip":"invalid-v4"}"#),
            ipv6.absoluteString: response(#"{"ip":"invalid-v6"}"#),
            domestic.absoluteString: response(#"{"ret":"ok","data":{"ip":"invalid-domestic","location":[]}}"#)
        ])
        let probe = IPifyExitAddressProbe(
            client: client,
            ipv4Endpoint: ipv4,
            ipv6Endpoint: ipv6,
            domesticEndpoint: domestic
        )

        do {
            _ = try await probe.fetchPrimaryAddress()
            XCTFail("Invalid address responses must fail")
        } catch let failure as NetworkFailure {
            XCTAssertEqual(failure, .invalidResponse)
        }
    }

    func testFallsBackToDomesticAddressWhenIPifyIsUnavailable() async throws {
        let ipv4 = try XCTUnwrap(URL(string: "https://example.test/v4"))
        let ipv6 = try XCTUnwrap(URL(string: "https://example.test/v6"))
        let domestic = try XCTUnwrap(URL(string: "https://example.test/domestic"))
        let client = RoutingHTTPClient(responses: [
            ipv4.absoluteString: response("unavailable", status: 503),
            ipv6.absoluteString: response("unavailable", status: 503),
            domestic.absoluteString: response(#"{"ret":"ok","data":{"ip":"180.173.166.20","location":["中国","上海","上海","","电信"]}}"#)
        ])
        let probe = IPifyExitAddressProbe(
            client: client,
            ipv4Endpoint: ipv4,
            ipv6Endpoint: ipv6,
            domesticEndpoint: domestic
        )

        let observation = try await probe.observeExit()

        XCTAssertEqual(observation.primaryAddress, "180.173.166.20")
        XCTAssertEqual(observation.routeMode, .direct)
        XCTAssertEqual(observation.preResolvedGeo?.location.city, "Shanghai")
    }
}

private actor SlowProbeHTTPClient: HTTPClient {
    private(set) var callCount = 0

    func data(for request: URLRequest) async throws -> HTTPResponse {
        callCount += 1
        try await Task.sleep(for: .seconds(5))
        return response(#"{"ip":"203.0.113.42"}"#)
    }
}
