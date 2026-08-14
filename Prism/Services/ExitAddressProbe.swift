import Foundation
import Network

protocol ExitAddressProbing: Sendable {
    func observeExit() async throws -> ExitObservation
}

extension ExitAddressProbing {
    func fetchPrimaryAddress() async throws -> String {
        try await observeExit().primaryAddress
    }
}

struct IPifyExitAddressProbe: ExitAddressProbing {
    private let client: any HTTPClient
    private let ipv4Endpoint: URL
    private let ipv6Endpoint: URL
    private let domesticEndpoint: URL

    init(
        client: any HTTPClient = URLSessionHTTPClient(
            requestTimeout: 2,
            sessionLifetime: .rotating(maxAge: 0.3)
        ),
        ipv4Endpoint: URL? = nil,
        ipv6Endpoint: URL? = nil,
        domesticEndpoint: URL? = nil
    ) {
        self.client = client
        self.ipv4Endpoint = ipv4Endpoint ?? Self.endpoint(host: "api.ipify.org")
        self.ipv6Endpoint = ipv6Endpoint ?? Self.endpoint(host: "api6.ipify.org")
        self.domesticEndpoint = domesticEndpoint ?? IPIPCurrentNetworkResponse.endpoint()
    }

    func observeExit() async throws -> ExitObservation {
        let overseas = await overseasAddresses()
        if let primaryAddress = overseas.preferredForLookup {
            try Task.checkCancellation()
            return ExitObservation(
                addresses: overseas,
                primaryAddress: primaryAddress,
                source: overseas.ipv4 == nil ? .overseasIPv6 : .overseasIPv4,
                routeMode: .proxy
            )
        }

        try Task.checkCancellation()
        return try await fetchDomesticFallback()
    }

    private func overseasAddresses() async -> IPAddressSet {
        async let ipv4 = try? fetch(endpoint: ipv4Endpoint, family: .ipv4)
        async let ipv6 = try? fetch(endpoint: ipv6Endpoint, family: .ipv6)
        let (ipv4Address, ipv6Address) = await (ipv4, ipv6)
        return IPAddressSet(ipv4: ipv4Address, ipv6: ipv6Address)
    }

    private func fetch(endpoint: URL, family: AddressFamily) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 1
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-store, no-cache", forHTTPHeaderField: "Cache-Control")
        let response = try await client.data(for: request)
        let payload: IPResponse
        do {
            payload = try JSONDecoder().decode(IPResponse.self, from: response.requireSuccess())
        } catch let error as NetworkFailure {
            throw error
        } catch {
            throw NetworkFailure.invalidResponse
        }

        let address = payload.ip.trimmingCharacters(in: .whitespacesAndNewlines)
        switch family {
        case .ipv4:
            guard IPv4Address(address) != nil else { throw NetworkFailure.invalidResponse }
        case .ipv6:
            guard IPv6Address(address) != nil else { throw NetworkFailure.invalidResponse }
        }
        return address
    }

    private func fetchDomesticFallback() async throws -> ExitObservation {
        var request = URLRequest(url: domesticEndpoint)
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-store, no-cache", forHTTPHeaderField: "Cache-Control")
        let response: IPIPCurrentNetworkResponse
        do {
            let data = try await client.data(for: request).requireSuccess()
            response = try JSONDecoder().decode(IPIPCurrentNetworkResponse.self, from: data)
        } catch {
            try Self.rethrowCancellationIfNeeded(error)
            throw NetworkFailure.serviceUnavailable
        }
        let address = response.data.ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard response.ret == "ok",
              IPv4Address(address) != nil || IPv6Address(address) != nil else {
            throw NetworkFailure.invalidResponse
        }
        let geo = try IPIPGeoProvider.result(from: response, matching: address)
        let addresses: IPAddressSet
        if IPv4Address(address) != nil {
            addresses = IPAddressSet(ipv4: address, ipv6: nil)
        } else {
            addresses = IPAddressSet(ipv4: nil, ipv6: address)
        }
        return ExitObservation(
            addresses: addresses,
            source: .domesticFallback,
            routeMode: .direct,
            preResolvedGeo: geo
        )
    }

    private static func rethrowCancellationIfNeeded(_ error: Error) throws {
        if Task.isCancelled || NetworkFailure.map(error) == .cancelled {
            throw CancellationError()
        }
    }

    private static func endpoint(host: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.queryItems = [URLQueryItem(name: "format", value: "json")]
        guard let url = components.url else {
            preconditionFailure("Invalid built-in ipify probe endpoint")
        }
        return url
    }

    private enum AddressFamily: Sendable {
        case ipv4
        case ipv6
    }

    private struct IPResponse: Decodable {
        let ip: String
    }
}
