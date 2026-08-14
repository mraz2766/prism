import XCTest
@testable import Prism

final class PublicIPServiceTests: XCTestCase {
    func testReturnsBothAddressFamilies() async throws {
        let v4 = try XCTUnwrap(URL(string: "https://example.test/v4"))
        let v6 = try XCTUnwrap(URL(string: "https://example.test/v6"))
        let client = RoutingHTTPClient(responses: [
            v4.absoluteString: response(#"{"ip":"203.0.113.2"}"#),
            v6.absoluteString: response(#"{"ip":"2001:db8::2"}"#)
        ])
        let service = PublicIPService(client: client, ipv4Endpoint: v4, ipv6Endpoint: v6)

        let addresses = try await service.fetchAddresses()

        XCTAssertEqual(addresses.ipv4, "203.0.113.2")
        XCTAssertEqual(addresses.ipv6, "2001:db8::2")
    }

    func testKeepsIPv4WhenIPv6Fails() async throws {
        let v4 = try XCTUnwrap(URL(string: "https://example.test/v4"))
        let v6 = try XCTUnwrap(URL(string: "https://example.test/v6"))
        let client = RoutingHTTPClient(responses: [
            v4.absoluteString: response(#"{"ip":"203.0.113.3"}"#),
            v6.absoluteString: response("not-json")
        ])
        let service = PublicIPService(client: client, ipv4Endpoint: v4, ipv6Endpoint: v6)

        let addresses = try await service.fetchAddresses()

        XCTAssertEqual(addresses.ipv4, "203.0.113.3")
        XCTAssertNil(addresses.ipv6)
    }

    func testUsesDomesticFallbackWhenBothIPifyFamiliesFail() async throws {
        let v4 = try XCTUnwrap(URL(string: "https://example.test/v4"))
        let v6 = try XCTUnwrap(URL(string: "https://example.test/v6"))
        let domestic = try XCTUnwrap(URL(string: "https://example.test/domestic"))
        let client = RoutingHTTPClient(responses: [
            v4.absoluteString: response("unavailable", status: 503),
            v6.absoluteString: response("unavailable", status: 503),
            domestic.absoluteString: response(#"{"ret":"ok","data":{"ip":"180.173.166.20","location":["中国","上海","上海","","电信"]}}"#)
        ])
        let service = PublicIPService(
            client: client,
            ipv4Endpoint: v4,
            ipv6Endpoint: v6,
            domesticEndpoint: domestic
        )

        let addresses = try await service.fetchAddresses()

        XCTAssertEqual(addresses, IPAddressSet(ipv4: "180.173.166.20", ipv6: nil))
    }
}
