import Foundation

struct IPAddressSet: Codable, Equatable, Sendable {
    let ipv4: String?
    let ipv6: String?

    var preferredForLookup: String? { ipv4 ?? ipv6 }
    var isEmpty: Bool { ipv4 == nil && ipv6 == nil }
}
