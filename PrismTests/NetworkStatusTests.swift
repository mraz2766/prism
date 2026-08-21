import XCTest
@testable import Prism

final class NetworkStatusTests: XCTestCase {
    func testOfflineRetainsComparisonDataWithoutExposingItAsCurrentInfo() {
        let status = NetworkStatus.offline(previous: .preview)

        XCTAssertNil(status.info)
        XCTAssertEqual(status.retainedInfo, .preview)
        XCTAssertTrue(status.isOffline)
    }

    func testOnlineAndVerifyingContinueToExposeCurrentPresentationData() {
        XCTAssertEqual(NetworkStatus.online(.preview).info, .preview)
        XCTAssertEqual(
            NetworkStatus.verifying(previous: .preview, candidateAddress: "198.51.100.20").info,
            .preview
        )
    }
}
