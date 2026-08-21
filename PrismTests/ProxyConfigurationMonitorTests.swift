import XCTest
@testable import Prism

@MainActor
final class ProxyConfigurationMonitorTests: XCTestCase {
    func testSystemConfigurationSubscriptionStartsAndStopsIdempotently() {
        let monitor = ProxyConfigurationMonitor()

        monitor.start()
        monitor.start()
        XCTAssertTrue(monitor.isMonitoring)

        monitor.stop()
        monitor.stop()
        XCTAssertFalse(monitor.isMonitoring)
    }

    func testRapidConfigurationNotificationsAreCoalesced() async throws {
        let monitor = ProxyConfigurationMonitor(debounce: .milliseconds(5))
        var events = monitor.events().makeAsyncIterator()

        monitor.receiveChange()
        monitor.receiveChange()
        monitor.receiveChange()

        let event = await events.next()
        XCTAssertEqual(event, .changed)
    }
}
