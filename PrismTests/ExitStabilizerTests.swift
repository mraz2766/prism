import XCTest
@testable import Prism

final class ExitStabilizerTests: XCTestCase {
    func testSameIPAddressStillConfirmsDomesticFallbackAndOverseasRecovery() {
        let addresses = IPAddressSet(ipv4: "198.51.100.30", ipv6: nil)
        for (from, to) in [(ExitSource.overseasIPv4, ExitSource.domesticFallback), (.domesticFallback, .overseasIPv4)] {
            var stabilizer = ExitStabilizer()
            let current = NetworkInfo(
                addresses: addresses, location: .unavailable, network: .unavailable,
                privacy: .unavailable, providerIdentifier: "", routeMode: .unknown,
                exitSource: from, checkedAt: .now
            )
            let candidate = ExitObservation(addresses: addresses, source: to, routeMode: .unknown)
            XCTAssertEqual(stabilizer.evaluate(candidate, currentInfo: current), .pending(candidate))
            XCTAssertEqual(stabilizer.evaluate(candidate, currentInfo: current), .confirmed(candidate))
        }
    }

    func testDifferentCandidateIPsDoNotCountAsTwoConfirmations() {
        var stabilizer = ExitStabilizer()
        let first = observation(ip: "198.51.100.30", route: .unknown)
        let second = observation(ip: "198.51.100.31", route: .unknown)
        XCTAssertEqual(stabilizer.evaluate(first, currentInfo: nil), .pending(first))
        XCTAssertEqual(stabilizer.evaluate(second, currentInfo: nil), .pending(second))
        XCTAssertEqual(stabilizer.evaluate(second, currentInfo: nil), .confirmed(second))
    }

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
