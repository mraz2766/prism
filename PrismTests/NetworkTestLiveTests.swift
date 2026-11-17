import XCTest
@testable import Prism

/// Opt-in integration checks; normal releases remain deterministic and do not contact these services.
@MainActor
final class NetworkTestLiveTests: XCTestCase {
    func testLiveHeadersAndWebKitICE() async throws {
        guard ProcessInfo.processInfo.environment["PRISM_LIVE_NETWORK_TESTS"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_PRISM_LIVE_NETWORK_TESTS=1 for live network validation")
        }
        let rtc = WebRTCProbe()
        async let report = rtc.collect()
        let result = try await NetworkTestService().measure(NetworkTestTarget.defaults[0], round: 1)
        XCTAssertNotNil(result.milliseconds, "The domestic reference should return headers: \(result.failure ?? "")")
        XCTAssertEqual(result.statusCode, 200)
        let ice = await report
        print("Prism live ICE: outcome=\(ice.outcome), candidate count=\(ice.candidates.count)")
        XCTAssertNotEqual(ice.outcome, .unavailable, "WebKit must expose RTCPeerConnection")
        XCTAssertNotEqual(ice.outcome, .cancelled)
        XCTAssertFalse(ice.candidates.isEmpty, "This live check requires at least one real ICE candidate")
    }
}
