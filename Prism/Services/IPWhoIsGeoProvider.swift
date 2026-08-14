import Foundation

struct IPWhoIsGeoProvider: GeoIPProvider {
    let identifier = "ipwho.is"
    private let client: any HTTPClient
    private let baseURL: URL

    init(
        client: any HTTPClient = URLSessionHTTPClient(requestTimeout: 1.5, sessionLifetime: .singleRequest),
        baseURL: URL? = nil
    ) {
        self.client = client
        self.baseURL = baseURL ?? Self.defaultBaseURL()
    }

    func lookup(ipAddress: String) async throws -> GeoIPResult {
        let url = baseURL.appendingPathComponent(ipAddress)
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-store, no-cache", forHTTPHeaderField: "Cache-Control")
        let data = try await client.data(for: request).requireSuccess()
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw NetworkFailure.invalidResponse
        }
        guard response.success != false,
              let countryCode = response.countryCode,
              !countryCode.isEmpty else {
            throw NetworkFailure.invalidResponse
        }
        return GeoIPResult(
            location: LocationInfo(
                countryCode: countryCode.uppercased(),
                region: response.region.nilIfEmpty,
                city: response.city.nilIfEmpty,
                timezone: response.timezone?.id.nilIfEmpty,
                latitude: response.latitude,
                longitude: response.longitude
            ),
            network: NetworkIdentity(
                isp: response.connection?.isp.nilIfEmpty,
                asn: response.connection?.asn,
                organization: response.connection?.org.nilIfEmpty,
                networkType: nil
            ),
            providerIdentifier: identifier
        )
    }

    private struct Response: Decodable {
        let success: Bool?
        let countryCode: String?
        let region: String?
        let city: String?
        let latitude: Double?
        let longitude: Double?
        let connection: Connection?
        let timezone: Timezone?

        enum CodingKeys: String, CodingKey {
            case success, region, city, latitude, longitude, connection, timezone
            case countryCode = "country_code"
        }
    }

    private struct Connection: Decodable {
        let asn: Int?
        let org: String?
        let isp: String?
    }

    private struct Timezone: Decodable { let id: String? }

    private static func defaultBaseURL() -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "ipwho.is"
        components.path = "/"
        guard let url = components.url else {
            preconditionFailure("Invalid built-in ipwho.is endpoint")
        }
        return url
    }
}

private extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
