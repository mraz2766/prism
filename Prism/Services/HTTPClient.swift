import Foundation

struct HTTPResponse: Sendable {
    let data: Data
    let statusCode: Int
}

protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> HTTPResponse
    func invalidateConnections() async
}

extension HTTPClient {
    func invalidateConnections() async {}
}

enum URLSessionLifetime: Equatable, Sendable {
    case persistent
    case singleRequest
    case rotating(maxAge: TimeInterval)
}

final class URLSessionHTTPClient: HTTPClient, @unchecked Sendable {
    private let sessionLifetime: URLSessionLifetime
    private let sessionFactory: @Sendable () -> URLSession
    private let uptime: @Sendable () -> TimeInterval
    private let stateLock = NSLock()
    private var sessionState: SessionState?

    init(
        requestTimeout: TimeInterval = 8,
        sessionLifetime: URLSessionLifetime = .persistent,
        sessionFactory: (@Sendable () -> URLSession)? = nil,
        uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        if case .rotating(let maxAge) = sessionLifetime {
            precondition(maxAge > 0)
        }
        self.sessionLifetime = sessionLifetime
        self.uptime = uptime
        let factory = sessionFactory ?? {
            URLSession(configuration: Self.configuration(requestTimeout: requestTimeout))
        }
        self.sessionFactory = factory
        switch sessionLifetime {
        case .persistent, .rotating:
            sessionState = SessionState(session: factory(), createdAt: uptime())
        case .singleRequest:
            sessionState = nil
        }
    }

    func data(for request: URLRequest) async throws -> HTTPResponse {
        let session = sessionForRequest()
        defer {
            if sessionLifetime == .singleRequest {
                session.invalidateAndCancel()
            }
        }
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkFailure.invalidResponse
        }
        return HTTPResponse(data: data, statusCode: httpResponse.statusCode)
    }

    func invalidateConnections() async {
        let previousSession = stateLock.withLock {
            let session = sessionState?.session
            sessionState = nil
            return session
        }
        previousSession?.invalidateAndCancel()
    }

    private func sessionForRequest() -> URLSession {
        switch sessionLifetime {
        case .singleRequest:
            return sessionFactory()
        case .persistent:
            return stateLock.withLock {
                if let sessionState { return sessionState.session }
                let state = SessionState(session: sessionFactory(), createdAt: uptime())
                sessionState = state
                return state.session
            }
        case .rotating(let maxAge):
            let now = uptime()
            var expiredSession: URLSession?
            let session = stateLock.withLock {
                if let sessionState, now - sessionState.createdAt < maxAge {
                    return sessionState.session
                }
                expiredSession = sessionState?.session
                let state = SessionState(session: sessionFactory(), createdAt: now)
                sessionState = state
                return state.session
            }
            expiredSession?.finishTasksAndInvalidate()
            return session
        }
    }

    private struct SessionState {
        let session: URLSession
        let createdAt: TimeInterval
    }

    private static func configuration(requestTimeout: TimeInterval) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpShouldUsePipelining = false
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout
        configuration.httpAdditionalHeaders = [
            "Accept": "application/json",
            "Cache-Control": "no-store, no-cache",
            "User-Agent": userAgent
        ]
        return configuration
    }

    /// 带真实版本号，便于排查各服务商的限流与兼容问题。
    static var userAgent: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "Prism/\(version) (\(build); macOS)"
    }
}

extension HTTPResponse {
    func requireSuccess() throws -> Data {
        guard (200..<300).contains(statusCode) else {
            throw NetworkFailure.serviceUnavailable
        }
        return data
    }
}
