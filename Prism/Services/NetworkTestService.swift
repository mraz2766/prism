import Foundation

protocol NetworkTestProbing: Sendable {
    func measure(_ target: NetworkTestTarget, round: Int) async throws -> NetworkTestSample
}

/// Each sample owns a fresh session. Stop at headers; never collect a response body.
struct NetworkTestService: NetworkTestProbing {
    private let configurationFactory: @Sendable () -> URLSessionConfiguration

    init(configurationFactory: @escaping @Sendable () -> URLSessionConfiguration = { .ephemeral }) {
        self.configurationFactory = configurationFactory
    }

    func measure(_ target: NetworkTestTarget, round: Int) async throws -> NetworkTestSample {
        try Task.checkCancellation()
        let configuration = configurationFactory()
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 4
        configuration.waitsForConnectivity = false
        var request = URLRequest(url: target.url)
        request.timeoutInterval = 4
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(URLSessionHTTPClient.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let response = try await HeaderOnlyRequest(request: request, configuration: configuration).execute()
            try Task.checkCancellation()
            let code = response.statusCode
            let accepted = target.expectedStatus.map { code == $0 } ?? (200..<300).contains(code)
            let failure: String?
            switch code {
            case _ where accepted: failure = nil
            case 404: failure = String(localized: "Test endpoint not found")
            case 403, 429: failure = String(localized: "Access restricted")
            default: failure = String(localized: "Unexpected HTTP status")
            }
            return NetworkTestSample(round: round, milliseconds: response.milliseconds, statusCode: code, failure: failure)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            return NetworkTestSample(round: round, milliseconds: nil, statusCode: nil, failure: Self.failureDescription(error))
        }
    }

    static func failureDescription(_ error: Error) -> String {
        switch (error as? URLError)?.code {
        case .timedOut: String(localized: "Request timed out")
        case .cannotFindHost, .dnsLookupFailed: String(localized: "DNS lookup failed")
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid: String(localized: "TLS verification failed")
        case .notConnectedToInternet, .networkConnectionLost: String(localized: "Network unavailable")
        default: String(localized: "Connection failed")
        }
    }
}

/// Reject body transfer as soon as Foundation delivers response headers.
/// State is protected by the lock across cancellation, URLSession callbacks and continuation setup.
private final class HeaderOnlyRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    struct Response: Sendable {
        let statusCode: Int
        let milliseconds: Double
    }

    private let request: URLRequest
    private let configuration: URLSessionConfiguration
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Response, any Error>?
    private var session: URLSession?
    private var cancelled = false
    private var startedAt = ContinuousClock.now

    init(request: URLRequest, configuration: URLSessionConfiguration) {
        self.request = request
        self.configuration = configuration
    }

    func execute() async throws -> Response {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                let task = session.dataTask(with: request)
                let canStart = lock.withLock {
                    guard !cancelled else { return false }
                    self.continuation = continuation
                    self.session = session
                    startedAt = .now
                    return true
                }
                if canStart { task.resume() }
                else {
                    session.invalidateAndCancel()
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            self.lock.withLock { self.cancelled = true }
            self.finish(.failure(CancellationError()))
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        let duration = lock.withLock { startedAt.duration(to: .now).components }
        let milliseconds = Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
        if let http = response as? HTTPURLResponse {
            finish(.success(.init(statusCode: http.statusCode, milliseconds: milliseconds)))
        } else { finish(.failure(URLError(.badServerResponse))) }
        completionHandler(.cancel)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        finish(.failure(error ?? URLError(.badServerResponse)))
    }

    private func finish(_ result: Result<Response, any Error>) {
        let pending = lock.withLock { () -> (CheckedContinuation<Response, any Error>, URLSession?)? in
            guard let continuation else { return nil }
            let session = self.session
            self.continuation = nil
            self.session = nil
            return (continuation, session)
        }
        pending?.1?.invalidateAndCancel()
        pending?.0.resume(with: result)
    }
}

struct PreviewNetworkTestProbe: NetworkTestProbing {
    func measure(_ target: NetworkTestTarget, round: Int) async throws -> NetworkTestSample {
        try await Task.sleep(for: .milliseconds(750))
        let base = target.id == "baidu" ? 42.0 : 185.0
        return .init(round: round, milliseconds: base + Double([12, 38, 0][round - 1]), statusCode: target.expectedStatus ?? 200, failure: nil)
    }
}
