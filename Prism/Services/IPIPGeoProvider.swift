import Foundation
import Network

struct IPIPCurrentNetworkResponse: Decodable, Sendable {
    let ret: String
    let data: Payload

    struct Payload: Decodable, Sendable {
        let ip: String
        let location: [String]
    }

    static func endpoint() -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "myip.ipip.net"
        components.path = "/json"
        guard let url = components.url else {
            preconditionFailure("Invalid built-in IPIP endpoint")
        }
        return url
    }
}

struct IPIPGeoProvider: GeoIPProvider {
    static let providerIdentifier = "ipip.net"
    let identifier = Self.providerIdentifier
    private let client: any HTTPClient
    private let endpoint: URL

    init(
        client: any HTTPClient = URLSessionHTTPClient(
            requestTimeout: 1.5,
            sessionLifetime: .singleRequest
        ),
        endpoint: URL? = nil
    ) {
        self.client = client
        self.endpoint = endpoint ?? IPIPCurrentNetworkResponse.endpoint()
    }

    func lookup(ipAddress: String) async throws -> GeoIPResult {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 1.5
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-store, no-cache", forHTTPHeaderField: "Cache-Control")
        let response: IPIPCurrentNetworkResponse
        do {
            let data = try await client.data(for: request).requireSuccess()
            response = try JSONDecoder().decode(IPIPCurrentNetworkResponse.self, from: data)
        } catch let failure as NetworkFailure {
            throw failure
        } catch {
            throw NetworkFailure.invalidResponse
        }

        return try Self.result(from: response, matching: ipAddress)
    }

    static func result(
        from response: IPIPCurrentNetworkResponse,
        matching ipAddress: String
    ) throws -> GeoIPResult {
        let observedIP = response.data.ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard response.ret == "ok",
              observedIP == ipAddress,
              IPv4Address(observedIP) != nil || IPv6Address(observedIP) != nil else {
            throw NetworkFailure.invalidResponse
        }

        let location = response.data.location
        guard location[safe: 0]?.trimmingCharacters(in: .whitespacesAndNewlines) == "中国" else {
            throw NetworkFailure.invalidResponse
        }
        let region = Self.englishAdministrativeName(
            location[safe: 1],
            suffixes: ["特别行政区", "维吾尔自治区", "壮族自治区", "回族自治区", "自治区", "省", "市"]
        )
        let city = Self.englishAdministrativeName(
            location[safe: 2] ?? location[safe: 1],
            suffixes: ["哈萨克自治州", "蒙古族藏族自治州", "自治州", "地区", "市", "盟"]
        )
        let isp = location[safe: 4]?.nilIfWhitespace

        return GeoIPResult(
            location: LocationInfo(
                countryCode: "CN",
                region: region,
                city: city,
                timezone: "Asia/Shanghai",
                latitude: nil,
                longitude: nil
            ),
            network: NetworkIdentity(
                isp: isp,
                asn: nil,
                organization: isp,
                networkType: nil
            ),
            providerIdentifier: providerIdentifier
        )
    }

    static func englishAdministrativeName(_ source: String?, suffixes: [String]) -> String? {
        guard var value = source?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        for suffix in suffixes.sorted(by: { $0.count > $1.count }) where value.hasSuffix(suffix) {
            value.removeLast(suffix.count)
            break
        }
        guard !value.isEmpty else { return nil }
        let latin = value.applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripCombiningMarks, reverse: false) ?? value
        let words = latin
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        let joined = words.joined().lowercased()
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    var nilIfWhitespace: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
