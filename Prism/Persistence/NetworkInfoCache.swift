import Foundation
import OSLog

private struct LegacyCachedMetadata: Codable, Equatable, Sendable {
    let geo: GeoIPResult
    let privacy: PrivacyClassification
}

final class NetworkInfoCache: @unchecked Sendable {
    private let infoURL: URL
    private let privacyURL: URL
    private let legacyMetadataURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger = Logger(subsystem: "com.mraz.prism", category: "cache")

    init(directory: URL? = nil) {
        let base = directory ?? Self.defaultDirectory()
        infoURL = base.appendingPathComponent("last-network-info.json")
        privacyURL = base.appendingPathComponent("privacy-classifications.json")
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

    func loadPrivacyClassifications() -> [String: PrivacyClassification] {
        if let current = decode([String: PrivacyClassification].self, from: privacyURL) {
            removeLegacyGeoMetadataIfPresent()
            return current
        }

        guard let legacy = decode([String: LegacyCachedMetadata].self, from: legacyMetadataURL) else {
            return [:]
        }
        let migrated = legacy.mapValues(\.privacy)
        savePrivacyClassifications(migrated)
        removeLegacyGeoMetadataIfPresent()
        return migrated
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

    private func encode<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            logger.error("Unable to save \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
