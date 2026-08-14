import AppIntents
import Foundation
@testable import Prism

actor RoutingHTTPClient: HTTPClient {
    let responses: [String: HTTPResponse]

    init(responses: [String: HTTPResponse]) { self.responses = responses }

    func data(for request: URLRequest) async throws -> HTTPResponse {
        guard let url = request.url,
              let response = responses[url.absoluteString] else {
            throw NetworkFailure.serviceUnavailable
        }
        return response
    }
}

struct StubGeoProvider: GeoIPProvider {
    let identifier: String
    let result: Result<GeoIPResult, NetworkFailure>

    func lookup(ipAddress: String) async throws -> GeoIPResult { try result.get() }
}

func response(_ json: String, status: Int = 200) -> HTTPResponse {
    HTTPResponse(data: Data(json.utf8), statusCode: status)
}
