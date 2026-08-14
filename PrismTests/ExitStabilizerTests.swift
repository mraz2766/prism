import XCTest
@testable import Prism

final class ExitStabilizerTests: XCTestCase {
    func testRouteChangeRequiresTwoConsecutiveObservations() {
        var stabilizer = ExitStabilizer()
        let current = routedInfo(ip: "203.0.113.10", route: .proxy)
        let direct = observation(ip: "198.51.100.30", route: .direct)

        XCTAssertEqual(stabilizer.evaluate(direct, currentInfo: current), .pending(direct))
        XCTAssertEqual(stabilizer.evaluate(direct, currentInfo: current), .confirmed(direct))
    }

    func testReturnToCurrentExitCancelsPendingCandidate() {
        var stabilizer = ExitStabilizer()
        let current = routedInfo(ip: "203.0.113.10", route: .proxy)
        let direct = observation(ip: "198.51.100.30", route: .direct)
        let original = observation(ip: "203.0.113.10", route: .proxy)

        XCTAssertEqual(stabilizer.evaluate(direct, currentInfo: current), .pending(direct))
        XCTAssertEqual(stabilizer.evaluate(original, currentInfo: current), .cancelled)
    }

    func testSameRouteAddressChangeConfirmsImmediately() {
        var stabilizer = ExitStabilizer()
        let current = routedInfo(ip: "203.0.113.10", route: .proxy)
        let rotated = observation(ip: "203.0.113.11", route: .proxy)

        XCTAssertEqual(stabilizer.evaluate(rotated, currentInfo: current), .confirmed(rotated))
    }

    func testMatchingLegacyAddressAdoptsKnownRouteImmediately() {
        var stabilizer = ExitStabilizer()
        let current = routedInfo(ip: "203.0.113.10", route: .unknown)
        let observation = observation(ip: "203.0.113.10", route: .proxy)

        XCTAssertEqual(stabilizer.evaluate(observation, currentInfo: current), .confirmed(observation))
    }
}
