import CryptoKit
import Foundation
import Network
import XCTest
@testable import Prism

final class OfflineCountryLookupTests: XCTestCase {
    func testBundledDatabaseResolvesKnownCountriesWithoutAnHTTPClient() {
        let lookup = OfflineCountryLookup()
        XCTAssertEqual(OfflineCountryLookup.datasetDate, "2026-11")
        XCTAssertEqual(lookup.countryCode(for: "3.113.21.153"), "JP")
        XCTAssertEqual(lookup.countryCode(for: "2406:da14:c77:8e00:ee06:4169:52c7:d4e0"), "JP")
        XCTAssertEqual(lookup.countryCode(for: "180.173.166.20"), "CN")
        XCTAssertEqual(lookup.countryCode(for: "8.8.8.8"), "US")
        XCTAssertEqual(lookup.countryCode(for: "::ffff:3.113.21.153"), "JP")
    }

    func testBoundariesAndUnknownGapsDoNotBorrowNeighboringCountries() throws {
        let lookup = OfflineCountryLookup(data: try fixture())
        XCTAssertNil(lookup.countryCode(for: "1.0.0.9"))
        XCTAssertEqual(lookup.countryCode(for: "1.0.0.10"), "JP")
        XCTAssertEqual(lookup.countryCode(for: "1.0.0.19"), "JP")
        XCTAssertNil(lookup.countryCode(for: "1.0.0.20"))
        XCTAssertNil(lookup.countryCode(for: "1.0.0.29"))
        XCTAssertEqual(lookup.countryCode(for: "1.0.0.30"), "CN")
        XCTAssertNil(lookup.countryCode(for: "1.0.0.40"))
        XCTAssertNil(lookup.countryCode(for: "2406::f"))
        XCTAssertEqual(lookup.countryCode(for: "2406::10"), "JP")
        XCTAssertEqual(lookup.countryCode(for: "2406::1f"), "JP")
        XCTAssertNil(lookup.countryCode(for: "2406::20"))
    }

    func testReservedAddressesAndInvalidInputHaveNoCountry() {
        let lookup = OfflineCountryLookup()
        for address in [
            "", "Japan", "999.1.1.1", "0.0.0.0", "10.0.0.1", "127.0.0.1", "100.64.0.1",
            "169.254.1.1", "172.16.0.1", "192.168.0.1", "198.18.0.1", "192.0.2.1",
            "198.51.100.1", "203.0.113.1", "224.0.0.1", "255.255.255.255",
            "::", "::1", "::ffff:192.168.1.1", "fc00::1", "fe80::1", "ff02::1",
            "2001:db8::1", "2001:2::1", "2002::1", "3fff::1"
        ] {
            XCTAssertNil(lookup.countryCode(for: address), address)
        }
    }

    func testTruncatedCorruptOrUnsupportedDatabaseFailsClosed() throws {
        let data = try fixture()
        var corruptPayload = data
        corruptPayload[corruptPayload.count - 1] ^= 1
        var corruptHeader = data
        corruptHeader[8] = 255
        var unsupported = data
        unsupported[7] = 50
        for invalid in [Data(), Data(data.prefix(12)), Data(data.dropLast()), corruptPayload, corruptHeader, unsupported] {
            let lookup = OfflineCountryLookup(data: invalid)
            XCTAssertNil(lookup.countryCode(for: "1.0.0.10"))
            XCTAssertNil(lookup.countryCode(for: "2406::10"))
        }
        let missing = OfflineCountryLookup(fileURL: URL(fileURLWithPath: "/nonexistent/prism-country.prismdb"))
        XCTAssertNil(missing.countryCode(for: "3.113.21.153"))
    }

    func testFileLoadingHasTheSameOfflineLookupBehavior() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try fixture().write(to: file)
        let lookup = OfflineCountryLookup(fileURL: file)
        XCTAssertEqual(lookup.countryCode(for: " 1.0.0.10\n"), "JP")
        XCTAssertEqual(lookup.countryCode(for: "2406:0:0:0:0:0:0:10"), "JP")
    }

    private func fixture() throws -> Data {
        let ipv4: [(String, UInt8)] = [
            ("0.0.0.0", 0), ("1.0.0.10", 1), ("1.0.0.20", 0), ("1.0.0.30", 2), ("1.0.0.40", 0)
        ]
        let ipv6: [(String, UInt8)] = [("::", 0), ("2406::10", 1), ("2406::20", 0)]
        var prefix = Data("PRCN0001".utf8)
        for count in [ipv4.count, ipv6.count] {
            prefix.append(contentsOf: (0..<4).reversed().map { UInt8((count >> ($0 * 8)) & 255) })
        }
        prefix.append(contentsOf: Array("2026-11".utf8) + [0, 0, 2, 0, 0])
        var body = Data("JPCN".utf8)
        for (address, country) in ipv4 {
            body.append(try XCTUnwrap(IPv4Address(address)).rawValue)
            body.append(country)
        }
        for (address, country) in ipv6 {
            body.append(try XCTUnwrap(IPv6Address(address)).rawValue)
            body.append(country)
        }
        return prefix + Data(SHA256.hash(data: prefix + body)) + body
    }
}
