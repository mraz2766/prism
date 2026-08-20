import XCTest
@testable import Prism

final class NetworkHistoryStoreTests: XCTestCase {
    func testDeduplicatesAndCapsHistory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("history.json")
        let store = NetworkHistoryStore(fileURL: url, maximumEntries: 2, settlingDelay: .zero)

        let recordedBaseline = await store.recordIfChanged(.preview)
        let recordedDuplicate = await store.recordIfChanged(.preview)
        XCTAssertTrue(recordedBaseline)
        XCTAssertFalse(recordedDuplicate)

        let changedIP = NetworkInfo(
            addresses: IPAddressSet(ipv4: "203.0.113.20", ipv6: nil),
            location: NetworkInfo.preview.location,
            network: NetworkInfo.preview.network,
            privacy: .unavailable,
            providerIdentifier: "test",
            checkedAt: .now
        )
        let changedASN = NetworkInfo(
            addresses: changedIP.addresses,
            location: changedIP.location,
            network: NetworkIdentity(isp: "Test", asn: 64500, organization: "Test", networkType: nil),
            privacy: .unavailable,
            providerIdentifier: "test",
            checkedAt: .now
        )
        let recordedIPChange = await store.recordIfChanged(changedIP)
        let recordedASNChange = await store.recordIfChanged(changedASN)
        XCTAssertTrue(recordedIPChange)
        XCTAssertTrue(recordedASNChange)

        let entries = await store.snapshot()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.last?.asn, 64500)
    }

    func testCorruptFileLoadsAsEmpty() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("history.json")
        try Data("broken".utf8).write(to: url)

        let store = NetworkHistoryStore(fileURL: url)

        let entries = await store.snapshot()
        XCTAssertTrue(entries.isEmpty)
    }

    func testLegacyHistoryWithoutRouteFieldsLoadsAsUnknown() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("history.json")
        let fixture = LegacyHistoryEntryFixture(info: .preview)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([fixture]).write(to: url, options: .atomic)

        let entries = await NetworkHistoryStore(fileURL: url).snapshot()

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.routeMode, .unknown)
        XCTAssertEqual(entries.first?.exitSource, .unknown)
    }

    func testTransientExitChangeIsDiscardedWhenOriginalExitReturns() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = NetworkHistoryStore(
            fileURL: directory.appendingPathComponent("history.json"),
            settlingDelay: .milliseconds(30)
        )
        let baseline = NetworkInfo.preview
        let transient = changedInfo(ip: "203.0.113.20")

        let recordedBaseline = await store.recordIfChanged(baseline)
        let acceptedTransient = await store.recordIfChanged(transient)
        let acceptedReturn = await store.recordIfChanged(baseline)
        XCTAssertTrue(recordedBaseline)
        XCTAssertTrue(acceptedTransient)
        XCTAssertFalse(acceptedReturn)
        try await Task.sleep(for: .milliseconds(50))

        let entries = await store.snapshot()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.addresses, baseline.addresses)
    }

    func testStableExitChangeCommitsAfterSettlingDelay() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = NetworkHistoryStore(
            fileURL: directory.appendingPathComponent("history.json"),
            settlingDelay: .milliseconds(20)
        )
        let changed = changedInfo(ip: "203.0.113.20")

        let recordedBaseline = await store.recordIfChanged(.preview)
        let acceptedChange = await store.recordIfChanged(changed)
        let pendingCount = await store.snapshot().count
        XCTAssertTrue(recordedBaseline)
        XCTAssertTrue(acceptedChange)
        XCTAssertEqual(pendingCount, 1)
        try await Task.sleep(for: .milliseconds(40))

        let entries = await store.snapshot()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.last?.addresses, changed.addresses)
    }

    private func changedInfo(ip: String) -> NetworkInfo {
        NetworkInfo(
            addresses: IPAddressSet(ipv4: ip, ipv6: nil),
            location: NetworkInfo.preview.location,
            network: NetworkInfo.preview.network,
            privacy: .unavailable,
            providerIdentifier: "test",
            checkedAt: .now
        )
    }
}

private struct LegacyHistoryEntryFixture: Encodable {
    let id = UUID()
    let recordedAt = Date.now
    let addresses: IPAddressSet
    let countryCode: String
    let city: String?
    let asn: Int?

    init(info: NetworkInfo) {
        addresses = info.addresses
        countryCode = info.location.countryCode
        city = info.location.city
        asn = info.network.asn
    }
}
