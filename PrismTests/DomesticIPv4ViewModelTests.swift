import XCTest
@testable import Prism

@MainActor
final class DomesticIPv4ViewModelTests: XCTestCase {
    func testRefreshPublishesAvailableResult() async {
        let info = domesticInfo(address: "180.173.166.20")
        let viewModel = DomesticIPv4ViewModel(
            probe: SequenceDomesticIPv4Probe(results: [.success(info)])
        )

        await viewModel.refresh().value

        XCTAssertEqual(viewModel.status, .available(info))
    }

    func testFailureKeepsPreviousResultInMemory() async {
        let info = domesticInfo(address: "180.173.166.20")
        let viewModel = DomesticIPv4ViewModel(
            probe: SequenceDomesticIPv4Probe(results: [
                .success(info),
                .failure(.serviceUnavailable)
            ])
        )

        await viewModel.refresh().value
        await viewModel.refresh().value

        XCTAssertEqual(
            viewModel.status,
            .failed(previous: info, reason: .serviceUnavailable)
        )
    }

    func testOlderRequestCannotOverwriteNewerResult() async throws {
        let first = domesticInfo(address: "180.173.166.20")
        let second = domesticInfo(address: "180.173.166.21")
        let viewModel = DomesticIPv4ViewModel(
            probe: OutOfOrderDomesticIPv4Probe(first: first, second: second)
        )

        let firstTask = viewModel.refresh()
        try await Task.sleep(for: .milliseconds(5))
        let secondTask = viewModel.refresh()
        await secondTask.value
        await firstTask.value

        XCTAssertEqual(viewModel.status, .available(second))
    }

    func testOfflineCancelsRefreshAndMarksPreviousResult() async {
        let info = domesticInfo(address: "180.173.166.20")
        let viewModel = DomesticIPv4ViewModel(
            probe: SequenceDomesticIPv4Probe(results: [.success(info)])
        )
        await viewModel.refresh().value

        viewModel.markOffline()

        XCTAssertEqual(viewModel.status, .failed(previous: info, reason: .offline))
    }
}

private actor SequenceDomesticIPv4Probe: DomesticIPv4Probing {
    private var results: [Result<DomesticIPv4Info, NetworkFailure>]

    init(results: [Result<DomesticIPv4Info, NetworkFailure>]) {
        self.results = results
    }

    func fetch() async throws -> DomesticIPv4Info {
        guard !results.isEmpty else { throw NetworkFailure.serviceUnavailable }
        return try results.removeFirst().get()
    }
}

private actor OutOfOrderDomesticIPv4Probe: DomesticIPv4Probing {
    let first: DomesticIPv4Info
    let second: DomesticIPv4Info
    private var callCount = 0

    init(first: DomesticIPv4Info, second: DomesticIPv4Info) {
        self.first = first
        self.second = second
    }

    func fetch() async throws -> DomesticIPv4Info {
        callCount += 1
        if callCount == 1 {
            try? await Task.sleep(for: .milliseconds(50))
            return first
        }
        return second
    }
}

private func domesticInfo(address: String) -> DomesticIPv4Info {
    DomesticIPv4Info(address: address, isChinese: true, checkedAt: .now)
}
