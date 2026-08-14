import XCTest
@testable import Prism

final class PrivacyClassificationServiceTests: XCTestCase {
    func testClassifiesAnyRiskSignalAsSuspected() async throws {
        let endpoint = try XCTUnwrap(URL(string: "https://example.test/privacy"))
        let requestURL = try XCTUnwrap(URL(string: "https://example.test/privacy?q=8.8.8.8"))
        let client = RoutingHTTPClient(responses: [
            requestURL.absoluteString: response(#"""
            {
              "is_datacenter": true,
              "is_tor": false,
              "is_proxy": false,
              "is_vpn": false
            }
            """#)
        ])
        let service = PrivacyClassificationService(client: client, endpoint: endpoint)

        let result = try await service.classify(ipAddress: "8.8.8.8")

        XCTAssertEqual(result, .suspected)
    }
}
