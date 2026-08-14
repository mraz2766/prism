import Foundation

struct NetworkInfo: Codable, Equatable, Sendable, Identifiable {
    let addresses: IPAddressSet
    let location: LocationInfo
    let network: NetworkIdentity
    let privacy: PrivacyClassification
    let providerIdentifier: String
    let routeMode: NetworkRouteMode
    let exitSource: ExitSource
    let checkedAt: Date

    init(
        addresses: IPAddressSet,
        location: LocationInfo,
        network: NetworkIdentity,
        privacy: PrivacyClassification,
        providerIdentifier: String,
        routeMode: NetworkRouteMode = .unknown,
        exitSource: ExitSource = .unknown,
        checkedAt: Date
    ) {
        self.addresses = addresses
        self.location = location
        self.network = network
        self.privacy = privacy
        self.providerIdentifier = providerIdentifier
        self.routeMode = routeMode
        self.exitSource = exitSource
        self.checkedAt = checkedAt
    }

    var id: String {
        [addresses.ipv4, addresses.ipv6, location.countryCode, network.asn.map(String.init)]
            .compactMap { $0 }
            .joined(separator: "|")
    }

    func updatingCheckedAt(_ date: Date) -> NetworkInfo {
        NetworkInfo(
            addresses: addresses,
            location: location,
            network: network,
            privacy: privacy,
            providerIdentifier: providerIdentifier,
            routeMode: routeMode,
            exitSource: exitSource,
            checkedAt: date
        )
    }

    private enum CodingKeys: String, CodingKey {
        case addresses, location, network, privacy, providerIdentifier, routeMode, exitSource, checkedAt
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        addresses = try values.decode(IPAddressSet.self, forKey: .addresses)
        location = try values.decode(LocationInfo.self, forKey: .location)
        network = try values.decode(NetworkIdentity.self, forKey: .network)
        privacy = try values.decode(PrivacyClassification.self, forKey: .privacy)
        providerIdentifier = try values.decode(String.self, forKey: .providerIdentifier)
        routeMode = try values.decodeIfPresent(NetworkRouteMode.self, forKey: .routeMode) ?? .unknown
        exitSource = try values.decodeIfPresent(ExitSource.self, forKey: .exitSource) ?? .unknown
        checkedAt = try values.decode(Date.self, forKey: .checkedAt)
    }

    static let preview = NetworkInfo(
        addresses: IPAddressSet(ipv4: "103.21.244.8", ipv6: "2400:cb00:2048:1::c629:d7a2"),
        location: LocationInfo(
            countryCode: "JP",
            region: "Tokyo",
            city: "Tokyo",
            timezone: "Asia/Tokyo",
            latitude: 35.6762,
            longitude: 139.6503
        ),
        network: NetworkIdentity(
            isp: "Example Network",
            asn: 13335,
            organization: "Example Organization",
            networkType: "ISP"
        ),
        privacy: .suspected,
        providerIdentifier: "ipwho.is",
        checkedAt: .now
    )
}
