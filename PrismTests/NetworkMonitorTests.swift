import XCTest
@testable import Prism

@MainActor
final class NetworkMonitorTests: XCTestCase {
    func testTransientOfflineIsCancelledByFastRecovery() async throws {
        let monitor = NetworkMonitor(
            offlineDebounce: .milliseconds(30),
            onlineDebounce: .milliseconds(5)
        )
        var events = monitor.events().makeAsyncIterator()

        monitor.receiveConnectivity(isSatisfied: false)
        try await Task.sleep(for: .milliseconds(5))
        monitor.receiveConnectivity(isSatisfied: true)

        let event = await events.next()
        XCTAssertEqual(event, .onlineChanged)
    }

    func testSustainedOfflinePublishesOffline() async {
        let monitor = NetworkMonitor(
            offlineDebounce: .milliseconds(5),
            onlineDebounce: .milliseconds(5)
        )
        var events = monitor.events().makeAsyncIterator()

        monitor.receiveConnectivity(isSatisfied: false)

        let event = await events.next()
        XCTAssertEqual(event, .offline)
    }
}
