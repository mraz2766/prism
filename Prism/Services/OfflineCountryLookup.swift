import CryptoKit
import Foundation
import Network

protocol CountryLookingUp: Sendable {
    func countryCode(for ipAddress: String) -> String?
}

/// A memory-mapped country-only index. Queries never open a socket or wait for GeoIP services.
struct OfflineCountryLookup: CountryLookingUp {
    static let attribution = "IP Geolocation by DB-IP"
    static let sourceURL = URL(string: "https://db-ip.com/db/download/ip-to-country-lite")!
    static let licenseURL = URL(string: "https://creativecommons.org/licenses/by/4.0/")!
    static var datasetDate: String { bundledStorage?.month ?? "—" }

    private let storage: Storage?
    private static let headerSize = 60
    private static let bundledStorage: Storage? = {
        let url = Bundle.main.url(forResource: "country-dbip", withExtension: "prismdb", subdirectory: "GeoIP")
            ?? Bundle.main.url(forResource: "country-dbip", withExtension: "prismdb")
        guard let url, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return parse(data)
    }()

    init() { storage = Self.bundledStorage }

    init(data: Data) { storage = Self.parse(data) }

    init(fileURL: URL) {
        storage = (try? Data(contentsOf: fileURL, options: .mappedIfSafe)).flatMap(Self.parse)
    }

    func countryCode(for ipAddress: String) -> String? {
        guard let storage else { return nil }
        let value = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if let ipv4 = IPv4Address(value) {
            let bytes = Array(ipv4.rawValue)
            guard Self.isPublicIPv4(bytes) else { return nil }
            return storage.lookup(bytes, width: 4, offset: storage.ipv4Offset, count: storage.ipv4Count)
        }
        guard let ipv6 = IPv6Address(value) else { return nil }
        let bytes = Array(ipv6.rawValue)
        // IPv4-mapped IPv6 addresses identify the same IPv4 address, not a separate IPv6 location.
        if bytes.prefix(10).allSatisfy({ $0 == 0 }), bytes[10] == 255, bytes[11] == 255 {
            let ipv4 = Array(bytes.suffix(4))
            guard Self.isPublicIPv4(ipv4) else { return nil }
            return storage.lookup(ipv4, width: 4, offset: storage.ipv4Offset, count: storage.ipv4Count)
        }
        // Currently allocated global unicast space; exclude documentation and transition-only ranges.
        guard bytes[0] & 0xe0 == 0x20,
              !(bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8),
              !(bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] < 2),
              !(bytes[0] == 0x20 && bytes[1] == 0x02),
              !(bytes[0] == 0x3f && bytes[1] == 0xff && bytes[2] & 0xf0 == 0) else { return nil }
        return storage.lookup(bytes, width: 16, offset: storage.ipv6Offset, count: storage.ipv6Count)
    }

    private static func isPublicIPv4(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 4 else { return false }
        let a = bytes[0], b = bytes[1], c = bytes[2]
        return a != 0 && a != 10 && a != 127 && a < 224
            && !(a == 100 && (64...127).contains(b))
            && !(a == 169 && b == 254)
            && !(a == 172 && (16...31).contains(b))
            && !(a == 192 && b == 168)
            && !(a == 192 && b == 0 && (c == 0 || c == 2))
            && !(a == 192 && b == 88 && c == 99)
            && !(a == 198 && (b == 18 || b == 19))
            && !(a == 198 && b == 51 && c == 100)
            && !(a == 203 && b == 0 && c == 113)
    }

    private static func parse(_ data: Data) -> Storage? {
        guard data.count >= headerSize,
              Array(data.prefix(8)) == Array("PRCN0001".utf8) else { return nil }
        func byte(_ index: Int) -> UInt8 { data[data.startIndex + index] }
        func integer(_ offset: Int, count: Int) -> Int {
            (offset..<(offset + count)).reduce(0) { ($0 << 8) | Int(byte($1)) }
        }
        let ipv4Count = integer(8, count: 4), ipv6Count = integer(12, count: 4)
        let countriesCount = integer(24, count: 2)
        guard ipv4Count > 0, ipv4Count <= 2_000_000,
              ipv6Count > 0, ipv6Count <= 2_000_000,
              (1...249).contains(countriesCount), integer(26, count: 2) == 0,
              data.count == headerSize + countriesCount * 2 + ipv4Count * 5 + ipv6Count * 17 else { return nil }
        let monthBytes = (16..<23).map(byte)
        guard byte(23) == 0, monthBytes[4] == 45,
              monthBytes.enumerated().allSatisfy({ $0.offset == 4 || (48...57).contains($0.element) }),
              let month = String(bytes: monthBytes, encoding: .ascii),
              let monthNumber = Int(month.suffix(2)), (1...12).contains(monthNumber) else { return nil }
        var hasher = SHA256()
        hasher.update(data: data.prefix(28))
        hasher.update(data: data.dropFirst(headerSize))
        guard Array(hasher.finalize()) == (28..<headerSize).map(byte) else { return nil }
        var countries = [String]()
        countries.reserveCapacity(countriesCount)
        for index in 0..<countriesCount {
            let offset = headerSize + index * 2
            guard let code = String(bytes: [byte(offset), byte(offset + 1)], encoding: .ascii),
                  isoCountries.contains(code) else { return nil }
            countries.append(code)
        }
        guard Set(countries).count == countriesCount else { return nil }
        return Storage(data: data, countries: countries, month: month, ipv4Count: ipv4Count, ipv6Count: ipv6Count)
    }

    private struct Storage: Sendable {
        let data: Data
        let countries: [String]
        let month: String
        let ipv4Count: Int
        let ipv6Count: Int
        var ipv4Offset: Int { OfflineCountryLookup.headerSize + countries.count * 2 }
        var ipv6Offset: Int { ipv4Offset + ipv4Count * 5 }

        func lookup(_ address: [UInt8], width: Int, offset: Int, count: Int) -> String? {
            let stride = width + 1
            var lower = 0, upper = count
            // Find the last range boundary less than or equal to the queried address.
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                let position = data.startIndex + offset + middle * stride
                var isAfterAddress = false
                for index in 0..<width where data[position + index] != address[index] {
                    isAfterAddress = data[position + index] > address[index]
                    break
                }
                if isAfterAddress { upper = middle } else { lower = middle + 1 }
            }
            guard lower > 0 else { return nil }
            let country = Int(data[data.startIndex + offset + (lower - 1) * stride + width])
            guard country > 0, country <= countries.count else { return nil }
            return countries[country - 1]
        }
    }

    private static let isoCountries: Set<String> = Set("""
    AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ
    BR BS BT BV BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM
    DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS
    GT GU GW GY HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN
    KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ
    MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM
    PN PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV
    SX SY SZ TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI
    VN VU WF WS YE YT ZA ZM ZW
    """.split(whereSeparator: \.isWhitespace).map(String.init))
}
