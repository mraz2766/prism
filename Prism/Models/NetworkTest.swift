import Foundation
import Network

struct NetworkTestTarget: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let url: URL
    let expectedStatus: Int?

    static let defaults: [Self] = [
        .init(id: "bing", name: "Bing China", url: URL(string: "https://cn.bing.com/favicon.ico")!, expectedStatus: nil),
        .init(id: "google", name: "Google", url: URL(string: "https://www.google.com/generate_204")!, expectedStatus: 204),
        .init(id: "gemini", name: "Gemini", url: URL(string: "https://gemini.google.com/favicon.ico")!, expectedStatus: nil),
        .init(id: "openai", name: "OpenAI", url: URL(string: "https://chatgpt.com/favicon.ico")!, expectedStatus: nil)
    ]
}

struct NetworkTestSample: Identifiable, Equatable, Sendable {
    let round: Int
    let milliseconds: Double?
    let statusCode: Int?
    let failure: String?
    var id: Int { round }
    var succeeded: Bool { failure == nil && milliseconds != nil }
}

struct NetworkTestResult: Identifiable, Equatable, Sendable {
    let target: NetworkTestTarget
    var samples: [NetworkTestSample] = []
    var id: String { target.id }
    var successful: [Double] { samples.filter(\.succeeded).compactMap(\.milliseconds) }
    var median: Double? {
        let sorted = successful.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
    /// Range of successful samples, not packet-loss or RTP jitter.
    var spread: Double? {
        guard successful.count >= 2, let low = successful.min(), let high = successful.max() else { return nil }
        return high - low
    }
}

struct ICECandidate: Identifiable, Equatable, Sendable {
    let address: String
    let kind: String
    let transport: String
    var id: String { "\(kind)|\(transport)|\(address.lowercased())" }

    enum AddressScope: Sendable { case publicIPv4, publicIPv6, local, mdns, unknown }

    var scope: AddressScope {
        if address.lowercased().hasSuffix(".local") { return .mdns }
        if let ipv4 = IPv4Address(address) {
            let b = Array(ipv4.rawValue)
            if b[0] == 0 || b[0] == 10 || b[0] == 127 || b[0] >= 224 ||
                (b[0] == 169 && b[1] == 254) || (b[0] == 172 && (16...31).contains(b[1])) ||
                (b[0] == 192 && b[1] == 168) || (b[0] == 100 && (64...127).contains(b[1])) {
                return .local
            }
            // Documentation, benchmark and special-use ranges are not evidence of public exposure.
            if (b[0] == 192 && b[1] == 0) || (b[0] == 198 && (b[1] == 18 || b[1] == 19)) ||
                (b[0] == 198 && b[1] == 51 && b[2] == 100) ||
                (b[0] == 203 && b[1] == 0 && b[2] == 113) { return .unknown }
            return .publicIPv4
        }
        if let ipv6 = IPv6Address(address) {
            let b = Array(ipv6.rawValue)
            if Array(b.prefix(12)) == [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 255] {
                return ICECandidate(address: b.suffix(4).map(String.init).joined(separator: "."), kind: kind, transport: transport).scope
            }
            if b[0] & 0xFE == 0xFC || (b[0] == 0xFE && b[1] & 0xC0 == 0x80) || b.dropLast().allSatisfy({ $0 == 0 }) {
                return .local
            }
            if b[0] & 0xE0 == 0x20, !(b[0] == 0x20 && b[1] == 0x01 && b[2] == 0x0D && b[3] == 0xB8) { return .publicIPv6 }
        }
        return .unknown
    }

    func matches(_ ip: String) -> Bool {
        if let a = IPv4Address(address), let b = IPv4Address(ip) { return a.rawValue == b.rawValue }
        if let a = IPv6Address(address), let b = IPv4Address(ip) {
            let bytes = Array(a.rawValue)
            return Array(bytes.prefix(12)) == [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 255] && Data(bytes.suffix(4)) == b.rawValue
        }
        if let a = IPv6Address(address), let b = IPv6Address(ip) { return a.rawValue == b.rawValue }
        return false
    }
}

struct WebRTCReport: Equatable, Sendable {
    enum Outcome: Equatable, Sendable { case complete, timedOut, unavailable, cancelled }
    var candidates: [ICECandidate] = []
    var outcome: Outcome = .complete

    enum Assessment: Equatable { case differentPath, matchesObservedExit, inconclusive }

    func assessment(httpAddresses: IPAddressSet) -> Assessment {
        guard outcome == .complete else { return .inconclusive }
        let publicCandidates = candidates.filter { $0.scope == .publicIPv4 || $0.scope == .publicIPv6 }
        guard !publicCandidates.isEmpty else { return .inconclusive }
        var allComparable = true
        for candidate in publicCandidates {
            let reference = candidate.scope == .publicIPv4 ? httpAddresses.ipv4 : httpAddresses.ipv6
            guard let reference else { allComparable = false; continue }
            if !candidate.matches(reference) { return .differentPath }
        }
        return allComparable ? .matchesObservedExit : .inconclusive
    }
}
