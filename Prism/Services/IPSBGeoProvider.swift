import Foundation
import Network

/// IP.SB accepts an explicit IPv4 or IPv6 address, so split routing cannot change the lookup target.
struct IPSBGeoProvider: GeoIPProvider {
    let identifier = "ip.sb"
    private let client: any HTTPClient
    private let baseURL: URL

    init(
        // 查询目标 IP 已写入 URL；复用连接可避免反复握手，代理节点变化也不会改变查询目标。
        client: any HTTPClient = URLSessionHTTPClient(requestTimeout: 1.5, sessionLifetime: .rotating(maxAge: 300)),
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
        guard Self.matches(response.ip, requested: ipAddress),
              let countryCode = response.countryCode?.uppercased(),
              countryCode.utf8.count == 2,
              countryCode.utf8.allSatisfy({ (65...90).contains($0) }) else {
            throw NetworkFailure.invalidResponse
        }
        return GeoIPResult(
            location: LocationInfo(
                countryCode: countryCode,
                region: response.region?.nilIfBlank,
                city: response.city?.nilIfBlank,
                timezone: response.timezone?.nilIfBlank,
                latitude: response.latitude,
                longitude: response.longitude
            ),
            network: NetworkIdentity(
                isp: response.isp?.nilIfBlank,
                asn: response.asn,
                organization: response.asnOrganization?.nilIfBlank ?? response.organization?.nilIfBlank,
                networkType: nil
            ),
            providerIdentifier: identifier
        )
    }

    private static func defaultBaseURL() -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.ip.sb"
        components.path = "/geoip/"
        guard let url = components.url else {
            preconditionFailure("Invalid built-in IP.SB endpoint")
        }
        return url
    }

    private static func matches(_ observed: String?, requested: String) -> Bool {
        guard let observed = observed?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        if let requestedIPv4 = IPv4Address(requested) {
            return IPv4Address(observed) == requestedIPv4
        }
        if let requestedIPv6 = IPv6Address(requested) {
            return IPv6Address(observed) == requestedIPv6
        }
        return false
    }

    private struct Response: Decodable {
        let ip: String?
        let countryCode: String?
        let region: String?
        let city: String?
        let timezone: String?
        let latitude: Double?
        let longitude: Double?
        let isp: String?
        let asn: Int?
        let organization: String?
        let asnOrganization: String?

        enum CodingKeys: String, CodingKey {
            case ip, region, city, timezone, latitude, longitude, isp, asn, organization
            case countryCode = "country_code"
            case asnOrganization = "asn_organization"
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
