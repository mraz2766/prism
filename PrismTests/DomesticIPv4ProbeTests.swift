import XCTest
@testable import Prism

final class DomesticIPv4ProbeTests: XCTestCase {
    func testParsesChineseIPv4AndDisablesCaching() async throws {
        let endpoint = try XCTUnwrap(URL(string: "https://example.test/domestic"))
        let client = RecordingDomesticHTTPClient(
            response: response(#"{"ret":"ok","data":{"ip":"180.173.166.20","location":["中国","上海","上海","","电信"]}}"#)
        )
        let probe = IPIPDomesticIPv4Probe(client: client, endpoint: endpoint)

        let info = try await probe.fetch()
        let request = await client.lastRequest

        XCTAssertEqual(info.address, "180.173.166.20")
        XCTAssertTrue(info.isChinese)
        XCTAssertEqual(request?.url, endpoint)
        XCTAssertEqual(request?.timeoutInterval, 2)
        XCTAssertEqual(request?.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Cache-Control"), "no-store, no-cache")
    }

    func testAcceptsNonChineseIPv4SoUICanExplainProxyRouting() async throws {
        let endpoint = try XCTUnwrap(URL(string: "https://example.test/domestic"))
        let client = RecordingDomesticHTTPClient(
            response: response(#"{"ret":"ok","data":{"ip":"203.0.113.40","location":["日本","东京","东京","","ISP"]}}"#)
        )
        let probe = IPIPDomesticIPv4Probe(client: client, endpoint: endpoint)

        let info = try await probe.fetch()

        XCTAssertEqual(info.address, "203.0.113.40")
        XCTAssertFalse(info.isChinese)
        XCTAssertEqual(info.relationship(to: "198.51.100.8"), .possiblyProxied)
    }

    func testRejectsIPv6BecauseTheFeatureIsExplicitlyIPv4() async throws {
        let endpoint = try XCTUnwrap(URL(string: "https://example.test/domestic"))
        let client = RecordingDomesticHTTPClient(
            response: response(#"{"ret":"ok","data":{"ip":"2001:db8::8","location":["中国","上海","上海"]}}"#)
        )
        let probe = IPIPDomesticIPv4Probe(client: client, endpoint: endpoint)

        do {
            _ = try await probe.fetch()
            XCTFail("IPv6 must not populate the domestic IPv4 row")
        } catch let failure as NetworkFailure {
            XCTAssertEqual(failure, .invalidResponse)
        }
    }

    func testRelationshipDistinguishesIndependentAndSharedExits() {
        let info = DomesticIPv4Info(
            address: "180.173.166.20",
            isChinese: true,
            checkedAt: .now
        )

        XCTAssertEqual(info.relationship(to: nil), .domesticObserved)
        XCTAssertEqual(info.relationship(to: "203.0.113.40"), .independentDomesticExit)
        XCTAssertEqual(info.relationship(to: "180.173.166.20"), .sameAsCurrentExit)
    }
}

private actor RecordingDomesticHTTPClient: HTTPClient {
    let response: HTTPResponse
    private(set) var lastRequest: URLRequest?

    init(response: HTTPResponse) {
        self.response = response
    }

    func data(for request: URLRequest) async throws -> HTTPResponse {
        lastRequest = request
        return response
    }
}
