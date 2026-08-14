import Foundation
import Network

protocol PublicIPProviding: Sendable {
    func fetchAddresses() async throws -> IPAddressSet
}

struct PublicIPService: PublicIPProviding {
    private let client: any HTTPClient
    private let ipv4Endpoint: URL
    private let ipv6Endpoint: URL
    private let domesticEndpoint: URL

    init(
        client: any HTTPClient = URLSessionHTTPClient(sessionLifetime: .singleRequest),
        ipv4Endpoint: URL? = nil,
        ipv6Endpoint: URL? = nil,
        domesticEndpoint: URL? = nil
    ) {
        self.client = client
        self.ipv4Endpoint = ipv4Endpoint ?? Self.endpoint(host: "api.ipify.org")
        self.ipv6Endpoint = ipv6Endpoint ?? Self.endpoint(host: "api6.ipify.org")
        self.domesticEndpoint = domesticEndpoint ?? IPIPCurrentNetworkResponse.endpoint()
    }

    func fetchAddresses() async throws -> IPAddressSet {
        async let ipv4Attempt = attempt(endpoint: ipv4Endpoint, family: .ipv4)
        async let ipv6Attempt = attempt(endpoint: ipv6Endpoint, family: .ipv6)
        let (ipv4, ipv6) = try await (ipv4Attempt, ipv6Attempt)
        try Task.checkCancellation()
        let addresses = IPAddressSet(ipv4: ipv4, ipv6: ipv6)
        if !addresses.isEmpty { return addresses }
        return try await fetchDomesticFallback()
    }

    private func attempt(endpoint: URL, family: AddressFamily) async throws -> String? {
        do {
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 1
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("no-store, no-cache", forHTTPHeaderField: "Cache-Control")
            let response = try await client.data(for: request)
            let payload = try JSONDecoder().decode(IPResponse.self, from: response.requireSuccess())
            let value = payload.ip.trimmingCharacters(in: .whitespacesAndNewlines)
            switch family {
            case .ipv4: return IPv4Address(value) == nil ? nil : value
            case .ipv6: return IPv6Address(value) == nil ? nil : value
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    private func fetchDomesticFallback() async throws -> IPAddressSet {
        var request = URLRequest(url: domesticEndpoint)
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-store, no-cache", forHTTPHeaderField: "Cache-Control")
        let response: IPIPCurrentNetworkResponse
        do {
            let data = try await client.data(for: request).requireSuccess()
            response = try JSONDecoder().decode(IPIPCurrentNetworkResponse.self, from: data)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw NetworkFailure.serviceUnavailable
        }
        let value = response.data.ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard response.ret == "ok" else { throw NetworkFailure.invalidResponse }
        if IPv4Address(value) != nil { return IPAddressSet(ipv4: value, ipv6: nil) }
        if IPv6Address(value) != nil { return IPAddressSet(ipv4: nil, ipv6: value) }
        throw NetworkFailure.invalidResponse
    }

    private enum AddressFamily { case ipv4, ipv6 }
    private struct IPResponse: Decodable { let ip: String }

    private static func endpoint(host: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.queryItems = [URLQueryItem(name: "format", value: "json")]
        guard let url = components.url else {
            preconditionFailure("Invalid built-in ipify endpoint")
        }
        return url
    }
}
