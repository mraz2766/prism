import Foundation

enum ExitSource: String, Codable, Equatable, Sendable {
    case overseasIPv4
    case overseasIPv6
    case domesticFallback
    case unknown

    var label: String {
        switch self {
        case .overseasIPv4, .overseasIPv6: String(localized: "Overseas exit probe")
        case .domesticFallback: String(localized: "Mainland direct probe")
        case .unknown: String(localized: "Unknown")
        }
    }
}

enum NetworkRouteMode: String, Codable, Equatable, Sendable {
    case proxy
    case direct
    case split
    case unknown

    var label: String {
        switch self {
        case .proxy: String(localized: "Proxy exit")
        case .direct: String(localized: "Direct exit")
        case .split: String(localized: "Split routing")
        case .unknown: String(localized: "Unknown route")
        }
    }
}

struct ExitObservation: Equatable, Sendable {
    let addresses: IPAddressSet
    let primaryAddress: String
    let source: ExitSource
    let routeMode: NetworkRouteMode
    let observedAt: Date
    let preResolvedGeo: GeoIPResult?

    init(
        addresses: IPAddressSet,
        primaryAddress: String? = nil,
        source: ExitSource,
        routeMode: NetworkRouteMode,
        observedAt: Date = .now,
        preResolvedGeo: GeoIPResult? = nil
    ) {
        guard let primaryAddress = primaryAddress ?? addresses.preferredForLookup else {
            preconditionFailure("An exit observation requires a primary address")
        }
        self.addresses = addresses
        self.primaryAddress = primaryAddress
        self.source = source
        self.routeMode = routeMode
        self.observedAt = observedAt
        self.preResolvedGeo = preResolvedGeo
    }
}
