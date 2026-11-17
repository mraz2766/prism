import XCTest
@testable import Prism

final class NetworkTestStatisticsTests: XCTestCase {
    func testMedianAndRangeExcludeRestrictedAndMissingResponses() {
        let result = NetworkTestResult(target: NetworkTestTarget.defaults[0], samples: [
            sample(1, 100), sample(2, 300), sample(3, 900, failure: "HTTP 403"),
            .init(round: 4, milliseconds: nil, statusCode: nil, failure: "timeout")
        ])
        XCTAssertEqual(result.median, 200)
        XCTAssertEqual(result.spread, 200)
        XCTAssertEqual(result.successful.count, 2)
    }

    func testEmptyAndSingleSampleDoNotInventStability() {
        var result = NetworkTestResult(target: NetworkTestTarget.defaults[0])
        XCTAssertNil(result.median)
        XCTAssertNil(result.spread)
        result.samples = [sample(1, 81)]
        XCTAssertEqual(result.median, 81)
        XCTAssertNil(result.spread)
        result.samples += [sample(2, 42), sample(3, 120)]
        XCTAssertEqual(result.median, 81)
        XCTAssertEqual(result.spread, 78)
    }

    func testErrorClassificationPreservesTLSAndTimeoutMeaning() {
        XCTAssertEqual(NetworkTestService.failureDescription(URLError(.timedOut)), String(localized: "Request timed out"))
        XCTAssertEqual(NetworkTestService.failureDescription(URLError(.serverCertificateUntrusted)), String(localized: "TLS verification failed"))
        XCTAssertEqual(NetworkTestService.failureDescription(URLError(.cannotFindHost)), String(localized: "DNS lookup failed"))
    }

    private func sample(_ round: Int, _ ms: Double, failure: String? = nil) -> NetworkTestSample {
        .init(round: round, milliseconds: ms, statusCode: failure == nil ? 200 : 403, failure: failure)
    }
}

@MainActor
final class NetworkTestHTTPTests: XCTestCase {
    func testReturnsWithoutWaitingForResponseBodyCompletion() async throws {
        let result = try await service().measure(target(status: 200), round: 1)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.statusCode, 200)
        XCTAssertNotNil(result.milliseconds)
    }

    func testRestrictedResponseHasLatencyButIsNotSuccessful() async throws {
        let result = try await service().measure(target(status: 403), round: 1)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.statusCode, 403)
        XCTAssertNotNil(result.milliseconds)
        XCTAssertEqual(result.failure, String(localized: "Access restricted"))
    }

    func testUnexpected200CannotPassA204Probe() async throws {
        var testTarget = target(status: 200)
        testTarget = .init(id: testTarget.id, name: testTarget.name, url: testTarget.url, expectedStatus: 204)
        let result = try await service().measure(testTarget, round: 1)
        XCTAssertFalse(result.succeeded)
    }

    func testMissingEndpointIsNotReportedAsAProxyConnectionFailure() async throws {
        let result = try await service().measure(target(status: 404), round: 1)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.statusCode, 404)
        XCTAssertNotNil(result.milliseconds)
        XCTAssertEqual(result.failure, String(localized: "Test endpoint not found"))
    }

    private func service() -> NetworkTestService {
        NetworkTestService {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [HeadersOnlyURLProtocol.self]
            return configuration
        }
    }

    private func target(status: Int) -> NetworkTestTarget {
        .init(id: "test", name: "test", url: URL(string: "https://test.invalid/\(status)")!, expectedStatus: nil)
    }
}

private final class HeadersOnlyURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let response = HTTPURLResponse(url: url, statusCode: Int(url.lastPathComponent)!, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/octet-stream", "Content-Length": "10000000"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // An explicit MIME type avoids content sniffing. Never send the declared 10 MB
        // body or finish the response: the probe must cancel at headers.
    }
    override func stopLoading() {}
}

final class WebRTCAssessmentTests: XCTestCase {
    private let reference = IPAddressSet(ipv4: "8.8.8.8", ipv6: "2606:4700:4700::1111")
    private func candidate(_ address: String) -> ICECandidate { .init(address: address, kind: "srflx", transport: "udp") }

    func testPrivateAndMDNSOnlyAreInconclusive() {
        for address in ["10.0.0.1", "192.168.1.2", "172.16.0.1", "127.0.0.1", "169.254.1.2", "100.64.0.1", "fd00::1", "fe80::2", "::1", "abc.local", "not-an-address", "203.0.113.1", "2001:db8::1"] {
            XCTAssertEqual(WebRTCReport(candidates: [candidate(address)]).assessment(httpAddresses: reference), .inconclusive, address)
        }
    }

    func testDifferentAddressIsOnlyAPathDifference() {
        XCTAssertEqual(WebRTCReport(candidates: [candidate("1.1.1.1")]).assessment(httpAddresses: reference), .differentPath)
    }

    func testIPv6ComparisonIsCanonical() {
        let report = WebRTCReport(candidates: [candidate("2606:4700:4700:0:0:0:0:1111")])
        XCTAssertEqual(report.assessment(httpAddresses: reference), .matchesObservedExit)
    }

    func testIPv4MappedIPv6UsesIPv4Reference() {
        XCTAssertEqual(WebRTCReport(candidates: [candidate("::ffff:8.8.8.8")]).assessment(httpAddresses: reference), .matchesObservedExit)
    }

    func testMissingFamilyCannotBeMistakenForLeakOrSafeResult() {
        let report = WebRTCReport(candidates: [candidate("8.8.8.8"), candidate("2606:4700:4700::1111")])
        XCTAssertEqual(report.assessment(httpAddresses: .init(ipv4: "8.8.8.8", ipv6: nil)), .inconclusive)
        XCTAssertEqual(report.assessment(httpAddresses: .init(ipv4: nil, ipv6: nil)), .inconclusive)
    }

    func testInterruptedCollectionCannotClaimSafety() {
        for outcome in [WebRTCReport.Outcome.cancelled, .unavailable, .timedOut] {
            XCTAssertEqual(WebRTCReport(candidates: [candidate("8.8.8.8")], outcome: outcome).assessment(httpAddresses: reference), .inconclusive)
        }
    }
}

@MainActor
final class NetworkTestViewModelTests: XCTestCase {
    func testCompletesTwelveSamplesAndICEWithBoundedConcurrency() async {
        let probe = RecordingLatencyProbe()
        let model = NetworkTestViewModel(probe: probe, rtc: ImmediateRTCProbe())
        await model.start(httpAddresses: .init(ipv4: "8.8.8.8", ipv6: nil)).value
        XCTAssertEqual(model.phase, .completed)
        XCTAssertEqual(model.completedSamples, 12)
        XCTAssertEqual(model.progress, 1)
        XCTAssertNotNil(model.webRTC)
        let maximum = await probe.maximumConcurrent
        XCTAssertLessThanOrEqual(maximum, 2)
        XCTAssertTrue(model.results.allSatisfy { $0.samples.map(\.round) == [1, 2, 3] })
    }

    func testStopSuppressesLateResults() async throws {
        let model = NetworkTestViewModel(probe: RecordingLatencyProbe(ignoresCancellation: true), rtc: ImmediateRTCProbe())
        let task = model.start(httpAddresses: .init(ipv4: "8.8.8.8", ipv6: nil))
        try await Task.sleep(for: .milliseconds(10))
        model.stop()
        await task.value
        XCTAssertEqual(model.phase, .cancelled)
        XCTAssertEqual(model.completedSamples, 0)
        XCTAssertFalse(model.webRTCRunning)
    }

    func testRestartCannotMixOldSamplesIntoNewRun() async throws {
        let model = NetworkTestViewModel(probe: RecordingLatencyProbe(ignoresCancellation: true), rtc: ImmediateRTCProbe())
        let first = model.start(httpAddresses: .init(ipv4: "8.8.8.8", ipv6: nil))
        try await Task.sleep(for: .milliseconds(10))
        let second = model.start(httpAddresses: .init(ipv4: "1.1.1.1", ipv6: nil))
        await second.value
        await first.value
        XCTAssertEqual(model.phase, .completed)
        XCTAssertEqual(model.completedSamples, 12)
        XCTAssertEqual(model.httpAddresses.ipv4, "1.1.1.1")
    }

    func testNetworkChangeInvalidatesCompletedAndRunningResults() async {
        let model = NetworkTestViewModel(probe: RecordingLatencyProbe(), rtc: ImmediateRTCProbe())
        let reference = IPAddressSet(ipv4: "8.8.8.8", ipv6: nil)
        await model.start(httpAddresses: reference).value
        model.observedExitChanged(reference)
        XCTAssertEqual(model.phase, .completed)
        model.observedExitChanged(.init(ipv4: "1.1.1.1", ipv6: nil))
        XCTAssertEqual(model.phase, .invalidated)
        let next = model.start(httpAddresses: reference)
        model.invalidate()
        await next.value
        XCTAssertEqual(model.phase, .invalidated)
        XCTAssertEqual(model.completedSamples, 0)
    }

    func testMissingAndRecoveredFamiliesDoNotExpireCompletedResults() async {
        let model = NetworkTestViewModel(probe: RecordingLatencyProbe(), rtc: ImmediateRTCProbe())
        let reference = IPAddressSet(ipv4: "8.8.8.8", ipv6: "2606:4700:4700::1111")
        await model.start(httpAddresses: reference).value
        for addresses in [
            IPAddressSet(ipv4: reference.ipv4, ipv6: nil),
            IPAddressSet(ipv4: nil, ipv6: reference.ipv6),
            IPAddressSet(ipv4: nil, ipv6: nil),
            reference
        ] {
            model.observedExitChanged(addresses)
            XCTAssertEqual(model.phase, .completed)
            XCTAssertEqual(model.completedSamples, 12)
            XCTAssertEqual(model.httpAddresses, reference)
        }
        // A new IPv6 after the missing sample must still invalidate the old test.
        model.observedExitChanged(.init(ipv4: reference.ipv4, ipv6: nil))
        model.observedExitChanged(.init(ipv4: reference.ipv4, ipv6: "2606:4700:4700::1001"))
        XCTAssertEqual(model.phase, .invalidated)
    }

    func testIncompleteObservationDoesNotCancelRunningTest() async {
        let model = NetworkTestViewModel(probe: RecordingLatencyProbe(), rtc: ImmediateRTCProbe())
        let task = model.start(httpAddresses: .init(ipv4: "8.8.8.8", ipv6: "2606:4700:4700::1111"))
        model.observedExitChanged(.init(ipv4: "8.8.8.8", ipv6: nil))
        XCTAssertEqual(model.phase, .running)
        await task.value
        XCTAssertEqual(model.phase, .completed)
        XCTAssertEqual(model.completedSamples, 12)
    }

    func testEquivalentIPv6SpellingDoesNotExpireResults() async {
        let model = NetworkTestViewModel(probe: RecordingLatencyProbe(), rtc: ImmediateRTCProbe())
        await model.start(httpAddresses: .init(ipv4: nil, ipv6: "2606:4700:4700::1111")).value
        model.observedExitChanged(.init(ipv4: nil, ipv6: "2606:4700:4700:0:0:0:0:1111"))
        XCTAssertEqual(model.phase, .completed)
    }

    func testNewFamilyBecomesComparableWithoutChangingWebRTCReference() async {
        let model = NetworkTestViewModel(probe: RecordingLatencyProbe(), rtc: ImmediateRTCProbe())
        let reference = IPAddressSet(ipv4: "8.8.8.8", ipv6: nil)
        await model.start(httpAddresses: reference).value
        model.observedExitChanged(.init(ipv4: reference.ipv4, ipv6: "2606:4700:4700::1111"))
        XCTAssertEqual(model.phase, .completed)
        XCTAssertEqual(model.httpAddresses, reference)
        model.observedExitChanged(.init(ipv4: reference.ipv4, ipv6: "2606:4700:4700::1001"))
        XCTAssertEqual(model.phase, .invalidated)
    }

    func testCancelledWebKitCollectionFinishesPromptly() async {
        let probe = WebRTCProbe()
        let task = Task { await probe.collect() }
        task.cancel()
        let report = await task.value
        XCTAssertEqual(report.outcome, .cancelled)
    }
}

private actor RecordingLatencyProbe: NetworkTestProbing {
    private var concurrent = 0
    private(set) var maximumConcurrent = 0
    let ignoresCancellation: Bool
    init(ignoresCancellation: Bool = false) { self.ignoresCancellation = ignoresCancellation }
    func measure(_ target: NetworkTestTarget, round: Int) async throws -> NetworkTestSample {
        concurrent += 1
        maximumConcurrent = max(maximumConcurrent, concurrent)
        defer { concurrent -= 1 }
        if ignoresCancellation { try? await Task.sleep(for: .milliseconds(30)) }
        else { try await Task.sleep(for: .milliseconds(5)) }
        return .init(round: round, milliseconds: Double(round * 20), statusCode: 200, failure: nil)
    }
}

@MainActor
private final class ImmediateRTCProbe: WebRTCProbing {
    func collect() async -> WebRTCReport { .init() }
    func cancel() {}
}
