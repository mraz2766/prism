import XCTest
@testable import Prism

final class NetworkInfoCacheTests: XCTestCase {
    func testConfirmingSameExitPreservesLocationTimestampAcrossPersistence() throws {
        let original = NetworkInfo.preview
        let updated = original.updatingCheckedAt(original.checkedAt.addingTimeInterval(60))
        let reloaded = try JSONDecoder().decode(NetworkInfo.self, from: JSONEncoder().encode(updated))

        XCTAssertEqual(reloaded.checkedAt, updated.checkedAt)
        XCTAssertEqual(reloaded.locationCheckedAt, original.locationCheckedAt)
        XCTAssertNotEqual(reloaded.checkedAt, reloaded.locationCheckedAt)
    }

    func testConfirmedIPWithoutLocationRoundTripsWithoutInventingATimestamp() throws {
        let info = NetworkInfo(
            addresses: IPAddressSet(ipv4: "198.51.100.99", ipv6: nil),
            location: .unavailable,
            network: .unavailable,
            privacy: .unavailable,
            providerIdentifier: "",
            checkedAt: .now
        )
        let reloaded = try JSONDecoder().decode(NetworkInfo.self, from: JSONEncoder().encode(info))
        XCTAssertFalse(reloaded.hasLocation)
        XCTAssertNil(reloaded.locationCheckedAt)
        XCTAssertEqual(reloaded.addresses, info.addresses)
    }

    func testLegacyGeoMetadataPreservesLocationBeforeRemovingOldCombinedFile() throws {
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
        let location = try XCTUnwrap(cache.loadLocations()["198.51.100.40"])
        XCTAssertEqual(location.location.city, "Shanghai")
        XCTAssertEqual(location.source, .history)
        XCTAssertNil(location.recordedAt, "The old cache did not record a lookup timestamp")
        XCTAssertEqual(location.providerIdentifier, "ipwho.is")
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
        XCTAssertEqual(loaded.locationCheckedAt, loaded.checkedAt)
        XCTAssertEqual(loaded.locationSource, .online)
    }

    func testOfflineCountryDoesNotInventAnOnlineLookupTime() throws {
        let info = NetworkInfo(
            addresses: NetworkInfo.preview.addresses,
            location: NetworkInfo.preview.location,
            network: .unavailable,
            privacy: .unavailable,
            providerIdentifier: "offline-country",
            checkedAt: Date(timeIntervalSince1970: 2_000),
            locationCheckedAt: Date(timeIntervalSince1970: 1_000),
            locationSource: .offline
        )
        let reloaded = try JSONDecoder().decode(NetworkInfo.self, from: JSONEncoder().encode(info))
        XCTAssertTrue(reloaded.hasLocation)
        XCTAssertEqual(reloaded.locationSource, .offline)
        XCTAssertNil(reloaded.locationCheckedAt)
        XCTAssertNil(reloaded.updatingCheckedAt(Date(timeIntervalSince1970: 3_000)).locationCheckedAt)
    }

    func testExplicitHistoricalSourcePreservesUnknownTimestamp() throws {
        let info = NetworkInfo(
            addresses: NetworkInfo.preview.addresses,
            location: NetworkInfo.preview.location,
            network: .unavailable,
            privacy: .unavailable,
            providerIdentifier: "history",
            checkedAt: Date(timeIntervalSince1970: 2_000),
            locationCheckedAt: nil,
            locationSource: .history
        )
        let reloaded = try JSONDecoder().decode(NetworkInfo.self, from: JSONEncoder().encode(info))
        XCTAssertNil(reloaded.locationCheckedAt)
        XCTAssertEqual(reloaded.locationSource, .history)
        XCTAssertNil(reloaded.updatingCheckedAt(Date(timeIntervalSince1970: 3_000)).locationCheckedAt)
    }

    func testSuccessfulLocationSurvivesEmptyLatestSnapshotAndFailedCacheUpdates() throws {
        let cache = makeCache()
        let successful = cachedLocation(country: "JP", at: 1_000)
        cache.saveLocations(["198.51.100.10": successful])
        let emptyInfo = NetworkInfo(
            addresses: IPAddressSet(ipv4: "198.51.100.10", ipv6: nil),
            location: .unavailable, network: .unavailable, privacy: .unavailable,
            providerIdentifier: "", checkedAt: Date(timeIntervalSince1970: 2_000)
        )
        cache.saveInfo(emptyInfo)
        cache.saveLocations(["198.51.100.10": CachedLocation(info: emptyInfo)])

        XCTAssertEqual(cache.loadLocations()["198.51.100.10"], successful)
    }

    func testLatestSnapshotMigratesOnlyThePrimaryLookupAddress() throws {
        let cache = makeCache()
        cache.saveInfo(.preview)

        let locations = cache.loadLocations()
        XCTAssertNotNil(locations["203.0.113.8"])
        let ipv6Key = try XCTUnwrap(IPAddressKey.normalized("2001:db8::8"))
        XCTAssertNil(locations[ipv6Key], "A shared snapshot is not proof that the secondary IPv6 was geolocated")
    }

    func testEquivalentIPv6SpellingsShareOneRecordAndKeepTheNewerResult() throws {
        let cache = makeCache()
        let recent = cachedLocation(country: "JP", at: 2_000)
        cache.saveLocations(["2001:db8::1": recent])
        cache.saveLocations(["2001:0DB8:0:0:0:0:0:1": cachedLocation(country: "CN", at: 1_000)])
        let key = try XCTUnwrap(IPAddressKey.normalized("2001:db8::1"))

        let locations = cache.loadLocations()
        XCTAssertEqual(locations.count, 1)
        XCTAssertEqual(locations[key], recent)
        XCTAssertNil(IPAddressKey.normalized("not an IP"))
        XCTAssertNil(IPAddressKey.normalized("fe80::1%en0"))
    }

    func testSuccessCacheBoundsStorageByObservationTime() {
        let cache = makeCache()
        let locations = Dictionary(uniqueKeysWithValues: (0..<300).map { index in
            ("203.0.\(index / 256).\(index % 256)", cachedLocation(country: "JP", at: TimeInterval(index)))
        })
        cache.saveLocations(locations)
        let reloaded = cache.loadLocations()

        XCTAssertEqual(reloaded.count, 256)
        XCTAssertNil(reloaded["203.0.0.0"])
        XCTAssertNotNil(reloaded["203.0.1.43"])
    }

    func testHistoryMigrationPreservesOnlyActuallyRecordedFields() {
        let entry = NetworkHistoryEntry(recordedAt: Date(timeIntervalSince1970: 1_000), info: .preview)
        let cached = CachedLocation(historyEntry: entry)

        XCTAssertEqual(cached.source, .history)
        XCTAssertEqual(cached.recordedAt, entry.locationCheckedAt)
        XCTAssertEqual(cached.location.countryCode, entry.countryCode)
        XCTAssertEqual(cached.location.city, entry.city)
        XCTAssertEqual(cached.network.asn, entry.asn)
        XCTAssertNil(cached.location.timezone)
        XCTAssertNil(cached.location.latitude)
        XCTAssertNil(cached.network.isp)
        XCTAssertEqual(cached.providerIdentifier, "history")
    }

    func testOfflineHistoryCannotBecomeVerifiedLocationCache() throws {
        let info = NetworkInfo(
            addresses: NetworkInfo.preview.addresses,
            location: NetworkInfo.preview.location,
            network: .unavailable,
            privacy: .unavailable,
            providerIdentifier: "offline-country",
            checkedAt: Date(timeIntervalSince1970: 1_000),
            locationSource: .offline
        )
        let entry = NetworkHistoryEntry(recordedAt: Date(timeIntervalSince1970: 2_000), info: info)
        let reloaded = try JSONDecoder().decode(NetworkHistoryEntry.self, from: JSONEncoder().encode(entry))
        let cached = CachedLocation(historyEntry: reloaded)
        let cache = makeCache()
        cache.saveLocations(["203.0.113.8": cached])

        XCTAssertEqual(reloaded.locationSource, .offline)
        XCTAssertNil(reloaded.locationCheckedAt)
        XCTAssertEqual(cached.source, .offline)
        XCTAssertFalse(cached.isCacheable)
        XCTAssertTrue(cache.loadLocations().isEmpty)
    }

    func testOfflineEstimateCannotReplaceVerifiedCache() {
        let cache = makeCache()
        let verified = cachedLocation(country: "JP", at: 1_000)
        cache.saveLocations(["198.51.100.10": verified])
        let estimate = CachedLocation(
            location: NetworkInfo.preview.location, network: .unavailable,
            providerIdentifier: "offline-country", source: .offline,
            recordedAt: Date(timeIntervalSince1970: 2_000)
        )
        cache.saveLocations(["198.51.100.10": estimate])
        XCTAssertEqual(cache.loadLocations()["198.51.100.10"], verified)
    }

    private func makeCache() -> NetworkInfoCache {
        NetworkInfoCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    private func cachedLocation(country: String, at timestamp: TimeInterval) -> CachedLocation {
        CachedLocation(
            location: LocationInfo(countryCode: country, region: nil, city: nil, timezone: nil, latitude: nil, longitude: nil),
            network: .unavailable,
            providerIdentifier: "test",
            source: .online,
            recordedAt: Date(timeIntervalSince1970: timestamp)
        )
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
