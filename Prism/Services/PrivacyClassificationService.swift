import Foundation

protocol PrivacyClassifying: Sendable {
    func classify(ipAddress: String) async throws -> PrivacyClassification
}

struct PrivacyClassificationService: PrivacyClassifying {
    private let client: any HTTPClient
    private let endpoint: URL

    init(
        client: any HTTPClient = URLSessionHTTPClient(requestTimeout: 0.75),
        endpoint: URL? = nil
    ) {
        self.client = client
        self.endpoint = endpoint ?? Self.defaultEndpoint()
    }

    func classify(ipAddress: String) async throws -> PrivacyClassification {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "q", value: ipAddress)]
        guard let url = components?.url else { throw NetworkFailure.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.75
        let data = try await client.data(for: request).requireSuccess()
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw NetworkFailure.invalidResponse
        }
        return response.isVPN || response.isProxy || response.isTor || response.isDatacenter
            ? .suspected
            : .notDetected
    }

    private struct Response: Decodable {
        let isDatacenter: Bool
        let isTor: Bool
        let isProxy: Bool
        let isVPN: Bool

        enum CodingKeys: String, CodingKey {
            case isDatacenter = "is_datacenter"
            case isTor = "is_tor"
            case isProxy = "is_proxy"
            case isVPN = "is_vpn"
        }
    }

    private static func defaultEndpoint() -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.ipapi.is"
        components.path = "/"
        guard let url = components.url else {
            preconditionFailure("Invalid built-in ipapi.is endpoint")
        }
        return url
    }
}
