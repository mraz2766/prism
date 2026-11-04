import Foundation
import OSLog

private struct LegacyCachedMetadata: Codable, Equatable, Sendable {
    let geo: GeoIPResult
    let privacy: PrivacyClassification
}

final class NetworkInfoCache: @unchecked Sendable {
    private let infoURL: URL
    private let privacyURL: URL
    private let locationsURL: URL
    private let legacyMetadataURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger = Logger(subsystem: "com.mraz.prism", category: "cache")

    init(directory: URL? = nil) {
        let base = directory ?? Self.defaultDirectory()
        infoURL = base.appendingPathComponent("last-network-info.json")
        privacyURL = base.appendingPathComponent("privacy-classifications.json")
        locationsURL = base.appendingPathComponent("successful-locations.json")
        legacyMetadataURL = base.appendingPathComponent("lookup-metadata.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadInfo() -> NetworkInfo? { decode(NetworkInfo.self, from: infoURL) }

    func saveInfo(_ info: NetworkInfo) {
        encode(info, to: infoURL)
    }

    func loadLocations() -> [String: CachedLocation] {
        migrateLocations().records
    }

    /// Merge successful observations, retaining newer records and excluding failures/offline estimates.
    func saveLocations(_ locations: [String: CachedLocation]) {
        var merged = Self.normalizedLocations(decode([String: CachedLocation].self, from: locationsURL) ?? [:])
        for (address, location) in locations.sorted(by: { $0.key < $1.key }) {
            Self.merge(location, for: address, into: &merged)
        }
        encode(Self.trimmedLocations(merged), to: locationsURL)
    }

    func loadPrivacyClassifications() -> [String: PrivacyClassification] {
        // Do not discard the old Geo data until both independent stores have been migrated safely.
        let locationsPersisted = migrateLocations().persisted
        if let current = decode([String: PrivacyClassification].self, from: privacyURL) {
            if locationsPersisted { removeLegacyGeoMetadataIfPresent() }
            return current
        }

        guard let legacy = decode([String: LegacyCachedMetadata].self, from: legacyMetadataURL) else {
            return [:]
        }
        let migrated = legacy.mapValues(\.privacy)
        let keys = migrated.keys.sorted().suffix(50)
        let bounded = Dictionary(uniqueKeysWithValues: keys.compactMap { key in
            migrated[key].map { (key, $0) }
        })
        let privacyPersisted = encode(bounded, to: privacyURL)
        if locationsPersisted && privacyPersisted { removeLegacyGeoMetadataIfPresent() }
        return migrated
    }

    private func migrateLocations() -> (records: [String: CachedLocation], persisted: Bool) {
        let stored = decode([String: CachedLocation].self, from: locationsURL)
        var records = Self.normalizedLocations(stored ?? [:])
        if let info = loadInfo(), let address = info.addresses.preferredForLookup {
            Self.merge(CachedLocation(info: info), for: address, into: &records)
        }
        if let legacy = decode([String: LegacyCachedMetadata].self, from: legacyMetadataURL) {
            for (address, entry) in legacy.sorted(by: { $0.key < $1.key }) {
                Self.merge(CachedLocation(
                    location: entry.geo.location,
                    network: entry.geo.network,
                    providerIdentifier: entry.geo.providerIdentifier,
                    source: .history,
                    recordedAt: nil
                ), for: address, into: &records)
            }
        }
        records = Self.trimmedLocations(records)
        let persisted = stored == records || encode(records, to: locationsURL)
        return (records, persisted)
    }

    private static func normalizedLocations(_ locations: [String: CachedLocation]) -> [String: CachedLocation] {
        var normalized: [String: CachedLocation] = [:]
        for (address, location) in locations.sorted(by: { $0.key < $1.key }) {
            merge(location, for: address, into: &normalized)
        }
        return normalized
    }

    private static func merge(
        _ location: CachedLocation,
        for address: String,
        into locations: inout [String: CachedLocation]
    ) {
        guard location.isCacheable, let key = IPAddressKey.normalized(address) else { return }
        if let existing = locations[key] {
            let existingTime = existing.recordedAt ?? .distantPast
            let incomingTime = location.recordedAt ?? .distantPast
            if existingTime > incomingTime { return }
            if existingTime == incomingTime && existing.source == .online && location.source != .online { return }
        }
        locations[key] = location
    }

    private static func trimmedLocations(_ locations: [String: CachedLocation]) -> [String: CachedLocation] {
        let newest = locations.sorted { lhs, rhs in
            let lhsTime = lhs.value.recordedAt ?? .distantPast
            let rhsTime = rhs.value.recordedAt ?? .distantPast
            return lhsTime == rhsTime ? lhs.key < rhs.key : lhsTime > rhsTime
        }.prefix(256)
        return Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
    }

    func savePrivacyClassifications(_ classifications: [String: PrivacyClassification]) {
        let sortedKeys = classifications.keys.sorted().suffix(50)
        let trimmed = Dictionary(uniqueKeysWithValues: sortedKeys.compactMap { key in
            classifications[key].map { (key, $0) }
        })
        encode(trimmed, to: privacyURL)
    }

    private func removeLegacyGeoMetadataIfPresent() {
        guard FileManager.default.fileExists(atPath: legacyMetadataURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: legacyMetadataURL)
        } catch {
            logger.error("Unable to remove legacy GeoIP metadata: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try decoder.decode(type, from: Data(contentsOf: url))
        } catch {
            logger.error("Unable to decode \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    @discardableResult
    private func encode<T: Encodable>(_ value: T, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(value).write(to: url, options: .atomic)
            return true
        } catch {
            logger.error("Unable to save \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private static func defaultDirectory() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Prism", isDirectory: true)
    }
}
