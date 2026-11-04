import XCTest
@testable import Prism

final class IPSBGeoProviderTests: XCTestCase {
    func testMapsExplicitTargetResponseAndPreservesShortTimeout() async throws {
        let client = IPSBRecordingClient(response: response(#"""
        {"ip":"3.113.21.153","country_code":"JP","region":"Tokyo","city":"Tokyo",
         "timezone":"Asia/Tokyo","latitude":35.6893,"longitude":139.6899,
         "isp":"Amazon.com","asn":16509,"organization":"Amazon.com","asn_organization":"Amazon.com, Inc."}
        """#))
        let provider = IPSBGeoProvider(client: client)

        let result = try await provider.lookup(ipAddress: "3.113.21.153")
        let recordedRequest = await client.lastRequest
        let request = try XCTUnwrap(recordedRequest)

        XCTAssertEqual(request.url?.absoluteString, "https://api.ip.sb/geoip/3.113.21.153")
        XCTAssertEqual(request.timeoutInterval, 1.5)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store, no-cache")
        XCTAssertEqual(result.location.countryCode, "JP")
        XCTAssertEqual(result.location.city, "Tokyo")
        XCTAssertEqual(result.network.asn, 16509)
        XCTAssertEqual(result.network.organization, "Amazon.com, Inc.")
        XCTAssertEqual(result.providerIdentifier, "ip.sb")
    }

    func testAcceptsEquivalentIPv6AndMissingOptionalCity() async throws {
        let client = IPSBRecordingClient(response: response(#"{"ip":"2001:db8:0:0:0:0:0:1","country_code":"jp"}"#))
        let result = try await IPSBGeoProvider(client: client).lookup(ipAddress: "2001:db8::1")
        XCTAssertEqual(result.location.countryCode, "JP")
        XCTAssertNil(result.location.city)
        XCTAssertNil(result.network.asn)
    }

    func testRejectsWrongTargetAndErrorPayloads() async {
        for json in [
            #"{"ip":"180.173.166.20","country_code":"CN"}"#,
            #"{"ip":"3.113.21.153","country_code":"Japan"}"#,
            #"{"code":400,"message":"Invalid IP address"}"#,
            "not json"
        ] {
            let provider = IPSBGeoProvider(client: IPSBRecordingClient(response: response(json)))
            do {
                _ = try await provider.lookup(ipAddress: "3.113.21.153")
                XCTFail("Expected invalid response")
            } catch {
                XCTAssertEqual(NetworkFailure.map(error), .invalidResponse)
            }
        }
    }

    func testPreservesHTTPErrorStatus() async {
        let provider = IPSBGeoProvider(client: IPSBRecordingClient(response: response("{}", status: 429)))
        do {
            _ = try await provider.lookup(ipAddress: "3.113.21.153")
            XCTFail("Expected rate limit")
        } catch {
            XCTAssertEqual(NetworkFailure.map(error), .httpError(429))
        }
    }
}

private actor IPSBRecordingClient: HTTPClient {
    let response: HTTPResponse
    private(set) var lastRequest: URLRequest?

    init(response: HTTPResponse) { self.response = response }
    func data(for request: URLRequest) async throws -> HTTPResponse {
        lastRequest = request
        return response
    }
}
