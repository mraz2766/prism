import Foundation

struct NetworkHistoryEntry: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let recordedAt: Date
    let addresses: IPAddressSet
    let countryCode: String
    let city: String?
    let asn: Int?
    let routeMode: NetworkRouteMode
    let exitSource: ExitSource
    let locationSource: LocationSource
    /// Exact metadata lookup time, if available. Older history only provides recordedAt.
    let locationCheckedAt: Date?

    init(id: UUID = UUID(), recordedAt: Date = .now, info: NetworkInfo) {
        self.id = id
        self.recordedAt = recordedAt
        self.addresses = info.addresses
        self.countryCode = info.location.countryCode
        self.city = info.location.city
        self.asn = info.network.asn
        self.routeMode = info.routeMode
        self.exitSource = info.exitSource
        self.locationSource = info.locationSource
        self.locationCheckedAt = info.locationCheckedAt
    }

    func representsSameExit(as info: NetworkInfo) -> Bool {
        addresses == info.addresses &&
        routeMode == info.routeMode && exitSource == info.exitSource &&
        countryCode == info.location.countryCode &&
        asn == info.network.asn
    }

    func representsSameExit(as entry: NetworkHistoryEntry) -> Bool {
        addresses == entry.addresses &&
        routeMode == entry.routeMode && exitSource == entry.exitSource &&
        countryCode == entry.countryCode &&
        asn == entry.asn
    }

    private enum CodingKeys: String, CodingKey {
        case id, recordedAt, addresses, countryCode, city, asn, routeMode, exitSource, locationSource, locationCheckedAt
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        recordedAt = try values.decode(Date.self, forKey: .recordedAt)
        addresses = try values.decode(IPAddressSet.self, forKey: .addresses)
        countryCode = try values.decode(String.self, forKey: .countryCode)
        city = try values.decodeIfPresent(String.self, forKey: .city)
        asn = try values.decodeIfPresent(Int.self, forKey: .asn)
        routeMode = try values.decodeIfPresent(NetworkRouteMode.self, forKey: .routeMode) ?? .unknown
        exitSource = try values.decodeIfPresent(ExitSource.self, forKey: .exitSource) ?? .unknown
        locationSource = try values.decodeIfPresent(LocationSource.self, forKey: .locationSource)
            ?? (countryCode.isEmpty ? .unknown : .history)
        let storedLocationTime = try values.decodeIfPresent(Date.self, forKey: .locationCheckedAt)
        locationCheckedAt = locationSource == .offline || locationSource == .unknown ? nil : storedLocationTime
    }
}
