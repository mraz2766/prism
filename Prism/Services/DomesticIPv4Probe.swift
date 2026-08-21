import Foundation
import Network

protocol DomesticIPv4Probing: Sendable {
    func fetch() async throws -> DomesticIPv4Info
}

struct IPIPDomesticIPv4Probe: DomesticIPv4Probing {
    private let client: any HTTPClient
    private let endpoint: URL

    init(
        client: any HTTPClient = URLSessionHTTPClient(
            requestTimeout: 2,
            sessionLifetime: .singleRequest
        ),
        endpoint: URL? = nil
    ) {
        self.client = client
        self.endpoint = endpoint ?? IPIPCurrentNetworkResponse.endpoint()
    }

    func fetch() async throws -> DomesticIPv4Info {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-store, no-cache", forHTTPHeaderField: "Cache-Control")

        do {
            let data = try await client.data(for: request).requireSuccess()
            let response = try JSONDecoder().decode(IPIPCurrentNetworkResponse.self, from: data)
            let address = response.data.ip.trimmingCharacters(in: .whitespacesAndNewlines)
            guard response.ret == "ok", IPv4Address(address) != nil else {
                throw NetworkFailure.invalidResponse
            }
            let country = response.data.location.first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return DomesticIPv4Info(
                address: address,
                isChinese: country == "中国",
                checkedAt: .now
            )
        } catch {
            if Task.isCancelled || NetworkFailure.map(error) == .cancelled {
                throw CancellationError()
            }
            if let failure = error as? NetworkFailure { throw failure }
            throw NetworkFailure.invalidResponse
        }
    }
}
