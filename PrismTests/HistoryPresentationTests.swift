import XCTest
@testable import Prism

final class HistoryPresentationTests: XCTestCase {
    private func entry(
        _ ipv4: String,
        country: String = "JP",
        city: String? = "Tokyo",
        asn: Int? = 13335,
        at seconds: TimeInterval
    ) -> NetworkHistoryEntry {
        NetworkHistoryEntry(
            recordedAt: Date(timeIntervalSince1970: seconds),
            info: NetworkInfo(
                addresses: IPAddressSet(ipv4: ipv4, ipv6: nil),
                location: LocationInfo(countryCode: country, region: nil, city: city, timezone: nil, latitude: nil, longitude: nil),
                network: NetworkIdentity(isp: nil, asn: asn, organization: nil, networkType: nil),
                privacy: .unavailable,
                providerIdentifier: "test",
                routeMode: .proxy,
                exitSource: .overseasIPv4,
                checkedAt: Date(timeIntervalSince1970: seconds)
            )
        )
    }

    func testDwellRunsUntilTheNextEntryAndUntilNowForTheCurrentExit() {
        let rows = HistoryDisplayEntry.make(from: [
            entry("203.0.113.2", at: 4_000),
            entry("203.0.113.1", at: 1_000)
        ])
        XCTAssertEqual(rows.map(\.current.addresses.ipv4), ["203.0.113.1", "203.0.113.2"])
        XCTAssertNil(rows[0].previous)
        XCTAssertEqual(rows[0].dwell(), 3_000)
        XCTAssertFalse(rows[0].isCurrent)
        XCTAssertTrue(rows[1].isCurrent)
        XCTAssertEqual(rows[1].dwell(now: Date(timeIntervalSince1970: 4_600)), 600)
        XCTAssertEqual(rows[1].previous?.addresses.ipv4, "203.0.113.1")
    }

    func testSearchMatchesAddressCityCountryAndASNCaseInsensitively() {
        let item = entry("203.0.113.8", at: 0)
        XCTAssertTrue(item.matches(query: "113.8", localizedLocation: "日本 · 东京"))
        XCTAssertTrue(item.matches(query: "tokyo", localizedLocation: "日本 · 东京"))
        XCTAssertTrue(item.matches(query: "东京", localizedLocation: "日本 · 东京"))
        XCTAssertTrue(item.matches(query: "as13335", localizedLocation: "日本 · 东京"))
        XCTAssertTrue(item.matches(query: "jp", localizedLocation: "日本 · 东京"))
        XCTAssertFalse(item.matches(query: "osaka", localizedLocation: "日本 · 东京"))
    }

    func testCSVEscapesFieldsAndReportsDwellSeconds() {
        let rows = HistoryDisplayEntry.make(from: [
            entry("203.0.113.1", city: "Washington, D.C.", at: 0),
            entry("203.0.113.2", city: "The \"Loop\"", asn: nil, at: 120)
        ])
        let lines = HistoryCSV.make(rows, now: Date(timeIntervalSince1970: 180)).components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], HistoryCSV.header)
        XCTAssertEqual(lines[1], "1970-01-01T00:00:00Z,JP,\"Washington, D.C.\",203.0.113.1,,13335,proxy,overseasIPv4,120")
        XCTAssertEqual(lines[2], "1970-01-01T00:02:00Z,JP,\"The \"\"Loop\"\"\",203.0.113.2,,,proxy,overseasIPv4,60")
    }

    func testRemovingOneEntryKeepsTheRestAndPersists() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("prism-history-remove-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let first = entry("203.0.113.1", at: 0)
        let second = entry("203.0.113.2", at: 60)
        let store = NetworkHistoryStore(fileURL: url, settlingDelay: .zero, initialEntries: [first, second])

        await store.remove(id: first.id)
        await store.remove(id: UUID())

        let remaining = await store.snapshot()
        XCTAssertEqual(remaining.map(\.id), [second.id])
        let reloaded = await NetworkHistoryStore(fileURL: url, settlingDelay: .zero).snapshot()
        XCTAssertEqual(reloaded.map(\.id), [second.id])
    }

    func testDefaultCapacityKeepsFiveHundredEntries() {
        XCTAssertEqual(NetworkHistoryStore.defaultMaximumEntries, 500)
    }
}
