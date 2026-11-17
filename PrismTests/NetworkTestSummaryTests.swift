import XCTest
@testable import Prism

final class NetworkTestSummaryTests: XCTestCase {
    private func result(_ id: String, _ values: [Double?]) -> NetworkTestResult {
        let target = NetworkTestTarget.defaults.first { $0.id == id }!
        var result = NetworkTestResult(target: target)
        result.samples = values.enumerated().map { index, value in
            NetworkTestSample(
                round: index + 1,
                milliseconds: value,
                statusCode: value == nil ? nil : 200,
                failure: value == nil ? "timeout" : nil
            )
        }
        return result
    }

    func testQualityThresholdsFollowHTTPResponseTime() {
        XCTAssertEqual(NetworkTestQuality(milliseconds: 80), .excellent)
        XCTAssertEqual(NetworkTestQuality(milliseconds: 150), .good)
        XCTAssertEqual(NetworkTestQuality(milliseconds: 399), .good)
        XCTAssertEqual(NetworkTestQuality(milliseconds: 400), .fair)
        XCTAssertEqual(NetworkTestQuality(milliseconds: 900), .poor)
        XCTAssertLessThan(NetworkTestQuality.excellent, NetworkTestQuality.failed)
    }

    func testResultQualityDistinguishesPendingFromUnreachable() {
        XCTAssertNil(result("google", []).quality)
        XCTAssertEqual(result("google", [nil, nil]).quality, .failed)
        XCTAssertEqual(result("google", [nil, 120, 140]).quality, .excellent)
    }

    func testSummaryUsesTheMedianOfAllSuccessfulSamplesAndFindsTheFastestSite() {
        let summary = NetworkTestSummary(results: [
            result("baidu", [40, 50, 60]),
            result("google", [200, 220, 180]),
            result("openai", [nil, nil, nil])
        ])
        XCTAssertEqual(summary.completedSamples, 9)
        XCTAssertEqual(summary.successfulSamples, 6)
        XCTAssertEqual(summary.overallMedian, 120)
        XCTAssertEqual(summary.fastest?.id, "baidu")
        XCTAssertEqual(summary.successRate ?? 0, 6.0 / 9.0, accuracy: 0.0001)
        // 中位 0.12 s 本应“极佳”，但成功率不足 90%，至多“一般”。
        XCTAssertEqual(summary.quality, .fair)
    }

    func testLowSuccessRateOrNoSuccessDowngradesTheVerdict() {
        let mostlyFailed = NetworkTestSummary(results: [result("google", [100, nil, nil])])
        XCTAssertEqual(mostlyFailed.quality, .poor)

        let allFailed = NetworkTestSummary(results: [result("google", [nil, nil])])
        XCTAssertNil(allFailed.overallMedian)
        XCTAssertEqual(allFailed.quality, .failed)

        let empty = NetworkTestSummary(results: [result("google", [])])
        XCTAssertNil(empty.quality)
        XCTAssertNil(empty.successRate)
        XCTAssertNil(empty.fastest)
    }
}
