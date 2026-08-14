import Foundation

struct IPGuideGeoProvider: GeoIPProvider {
    let identifier = "ip.guide"
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
        var request = URLRequest(url: baseURL.appendingPathComponent(ipAddress))
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
        guard let countryCode = Self.countryCode(for: response.location.country) else {
            throw NetworkFailure.invalidResponse
        }
        let autonomousSystem = response.network.autonomousSystem
        return GeoIPResult(
            location: LocationInfo(
                countryCode: countryCode,
                region: nil,
                city: response.location.city?.nilIfBlank,
                timezone: response.location.timezone.nilIfBlank,
                latitude: response.location.latitude,
                longitude: response.location.longitude
            ),
            network: NetworkIdentity(
                isp: autonomousSystem.organization.nilIfBlank,
                asn: autonomousSystem.asn,
                organization: autonomousSystem.organization.nilIfBlank,
                networkType: nil
            ),
            providerIdentifier: identifier
        )
    }

    private static func countryCode(for englishName: String) -> String? {
        let needle = englishName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let locale = Locale(identifier: "en_US")
        if let match = Locale.Region.isoRegions.first(where: {
            $0.identifier.count == 2 && locale.localizedString(forRegionCode: $0.identifier)?.lowercased() == needle
        }) {
            return match.identifier.uppercased()
        }
        return [
            "china": "CN",
            "people's republic of china": "CN",
            "republic of korea": "KR",
            "taiwan, province of china": "TW",
            "macao": "MO",
            "viet nam": "VN",
            "czech republic": "CZ"
        ][needle]
    }

    private struct Response: Decodable {
        let network: Network
        let location: Location
    }

    private struct Network: Decodable {
        let autonomousSystem: AutonomousSystem
        enum CodingKeys: String, CodingKey { case autonomousSystem = "autonomous_system" }
    }

    private struct AutonomousSystem: Decodable {
        let asn: Int?
        let organization: String
    }

    private struct Location: Decodable {
        let city: String?
        let country: String
        let timezone: String
        let latitude: Double?
        let longitude: Double?
    }

    private static func defaultBaseURL() -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "ip.guide"
        components.path = "/"
        guard let url = components.url else {
            preconditionFailure("Invalid built-in ip.guide endpoint")
        }
        return url
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
