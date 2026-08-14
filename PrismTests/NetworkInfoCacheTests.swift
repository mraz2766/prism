import XCTest
@testable import Prism

final class NetworkInfoCacheTests: XCTestCase {
    func testLegacyGeoMetadataMigratesOnlyPrivacyAndRemovesCityData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacyURL = directory.appendingPathComponent("lookup-metadata.json")
        let privacyURL = directory.appendingPathComponent("privacy-classifications.json")
        let legacy = [
            "198.51.100.40": LegacyCacheFixture(
                geo: GeoIPResult(
                    location: LocationInfo(
                        countryCode: "CN",
                        region: "Shanghai",
                        city: "Shanghai",
                        timezone: "Asia/Shanghai",
                        latitude: 31.23,
                        longitude: 121.47
                    ),
                    network: NetworkInfo.preview.network,
                    providerIdentifier: "ipwho.is"
                ),
                privacy: .notDetected
            )
        ]
        try JSONEncoder().encode(legacy).write(to: legacyURL, options: .atomic)

        let cache = NetworkInfoCache(directory: directory)
        let migrated = cache.loadPrivacyClassifications()

        XCTAssertEqual(migrated["198.51.100.40"], .notDetected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: privacyURL.path))
        let persisted = try String(contentsOf: privacyURL, encoding: .utf8)
        XCTAssertFalse(persisted.contains("Shanghai"))
        XCTAssertFalse(persisted.contains("geo"))
    }

    func testLegacyNetworkInfoWithoutRouteFieldsLoadsAsUnknown() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let infoURL = directory.appendingPathComponent("last-network-info.json")
        let legacy = LegacyNetworkInfoFixture(info: .preview)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(legacy).write(to: infoURL, options: .atomic)

        let loaded = try XCTUnwrap(NetworkInfoCache(directory: directory).loadInfo())

        XCTAssertEqual(loaded.routeMode, .unknown)
        XCTAssertEqual(loaded.exitSource, .unknown)
        XCTAssertEqual(loaded.addresses, NetworkInfo.preview.addresses)
    }
}

private struct LegacyCacheFixture: Encodable {
    let geo: GeoIPResult
    let privacy: PrivacyClassification
}

private struct LegacyNetworkInfoFixture: Encodable {
    let addresses: IPAddressSet
    let location: LocationInfo
    let network: NetworkIdentity
    let privacy: PrivacyClassification
    let providerIdentifier: String
    let checkedAt: Date

    init(info: NetworkInfo) {
        addresses = info.addresses
        location = info.location
        network = info.network
        privacy = info.privacy
        providerIdentifier = info.providerIdentifier
        checkedAt = info.checkedAt
    }
}
