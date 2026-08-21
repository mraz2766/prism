import Foundation
import XCTest
@testable import Prism

final class HTTPClientTests: XCTestCase {
    func testSingleRequestLifetimeCreatesFreshSessionForEveryRequest() async throws {
        let factory = SessionFactoryCounter()
        let client = URLSessionHTTPClient(
            sessionLifetime: .singleRequest,
            sessionFactory: { factory.makeSession() }
        )
        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://prism.test/ip")))

        _ = try await client.data(for: request)
        _ = try await client.data(for: request)

        XCTAssertEqual(factory.count, 2)
    }

    func testPersistentLifetimeReusesOneSession() async throws {
        let factory = SessionFactoryCounter()
        let client = URLSessionHTTPClient(
            sessionLifetime: .persistent,
            sessionFactory: { factory.makeSession() }
        )
        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://prism.test/ip")))

        _ = try await client.data(for: request)
        _ = try await client.data(for: request)

        XCTAssertEqual(factory.count, 1)
    }

    func testRotatingLifetimeSharesAConnectionGenerationThenReplacesIt() async throws {
        let factory = SessionFactoryCounter()
        let uptime = MutableUptime()
        let client = URLSessionHTTPClient(
            sessionLifetime: .rotating(maxAge: 0.5),
            sessionFactory: { factory.makeSession() },
            uptime: { uptime.value }
        )
        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://prism.test/ip")))

        _ = try await client.data(for: request)
        _ = try await client.data(for: request)
        XCTAssertEqual(factory.count, 1)

        uptime.advance(by: 0.51)
        _ = try await client.data(for: request)

        XCTAssertEqual(factory.count, 2)
    }

    func testInvalidatingConnectionsForcesANewSessionGeneration() async throws {
        let factory = SessionFactoryCounter()
        let client = URLSessionHTTPClient(
            sessionLifetime: .persistent,
            sessionFactory: { factory.makeSession() }
        )
        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://prism.test/ip")))

        _ = try await client.data(for: request)
        await client.invalidateConnections()
        _ = try await client.data(for: request)

        XCTAssertEqual(factory.count, 2)
    }
}

private final class SessionFactoryCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var sessionCount = 0

    var count: Int { lock.withLock { sessionCount } }

    func makeSession() -> URLSession {
        lock.withLock { sessionCount += 1 }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SuccessfulURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class MutableUptime: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: TimeInterval = 0

    var value: TimeInterval { lock.withLock { storedValue } }

    func advance(by interval: TimeInterval) {
        lock.withLock { storedValue += interval }
    }
}

private final class SuccessfulURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
              ) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"ip":"203.0.113.1"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
