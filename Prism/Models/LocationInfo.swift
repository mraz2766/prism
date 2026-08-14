import Foundation

struct LocationInfo: Codable, Equatable, Sendable {
    let countryCode: String
    let region: String?
    let city: String?
    let timezone: String?
    let latitude: Double?
    let longitude: Double?

    func localizedCountry(locale: Locale = .autoupdatingCurrent) -> String {
        locale.localizedString(forRegionCode: countryCode.uppercased()) ?? countryCode.uppercased()
    }

    var cityAndCountryCode: String {
        guard let city, !city.isEmpty else { return countryCode.uppercased() }
        return "\(city), \(countryCode.uppercased())"
    }
}

struct NetworkIdentity: Codable, Equatable, Sendable {
    let isp: String?
    let asn: Int?
    let organization: String?
    let networkType: String?

    var asnLabel: String? { asn.map { "AS\($0)" } }
}

enum PrivacyClassification: String, Codable, Equatable, Sendable {
    case suspected
    case notDetected
    case unavailable
}

struct GeoIPResult: Codable, Equatable, Sendable {
    let location: LocationInfo
    let network: NetworkIdentity
    let providerIdentifier: String
}
