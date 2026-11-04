import Foundation
import Network

enum LocationSource: String, Codable, Equatable, Sendable {
    case online
    case history
    case offline
    case unknown
}

/// Only successful, IP-specific metadata belongs here; an exit probe's latest snapshot is separate.
struct CachedLocation: Codable, Equatable, Sendable {
    let location: LocationInfo
    let network: NetworkIdentity
    let providerIdentifier: String
    let source: LocationSource
    /// Online lookup time, or the time a historical observation was recorded; nil when unavailable.
    let recordedAt: Date?

    init(
        location: LocationInfo,
        network: NetworkIdentity,
        providerIdentifier: String,
        source: LocationSource,
        recordedAt: Date?
    ) {
        self.location = location
        self.network = network
        self.providerIdentifier = providerIdentifier
        self.source = source
        self.recordedAt = recordedAt
    }

    init(info: NetworkInfo) {
        self.init(
            location: info.location,
            network: info.network,
            providerIdentifier: info.providerIdentifier,
            source: info.locationSource,
            recordedAt: info.locationCheckedAt
        )
    }

    init(historyEntry: NetworkHistoryEntry) {
        self.init(
            location: LocationInfo(
                countryCode: historyEntry.countryCode,
                region: nil,
                city: historyEntry.city,
                timezone: nil,
                latitude: nil,
                longitude: nil
            ),
            network: NetworkIdentity(isp: nil, asn: historyEntry.asn, organization: nil, networkType: nil),
            providerIdentifier: "history",
            source: historyEntry.locationSource == .online ? .history : historyEntry.locationSource,
            recordedAt: historyEntry.locationCheckedAt ?? historyEntry.recordedAt
        )
    }

    var isCacheable: Bool {
        (source == .online || source == .history) &&
            Self.countryCodes.contains(location.countryCode.uppercased())
    }

    private static let countryCodes = Set(Locale.Region.isoRegions.map(\.identifier).filter { $0.count == 2 })
}

/// Canonical text keys make equivalent IPv6 spellings share one cache record.
/// IPv4 and IPv6 remain separate observations: a dual-stack snapshot does not prove both locations.
enum IPAddressKey {
    static func normalized(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.contains("%") else { return nil }
        if let address = IPv4Address(value) {
            return address.rawValue.map(String.init).joined(separator: ".")
        }
        guard let address = IPv6Address(value) else { return nil }
        let bytes = [UInt8](address.rawValue)
        return stride(from: 0, to: bytes.count, by: 2).map { offset in
            String(UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1]), radix: 16)
        }.joined(separator: ":")
    }
}
