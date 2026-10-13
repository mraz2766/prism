import Foundation
import Observation

@MainActor
@Observable
final class DomesticIPv4ViewModel {
    private(set) var status: DomesticIPv4Status = .idle

    @ObservationIgnored private let probe: any DomesticIPv4Probing
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var requestID: UUID?
    @ObservationIgnored private var lastRefreshStartedAt: ContinuousClock.Instant?
    @ObservationIgnored private let clock = ContinuousClock()

    init(probe: any DomesticIPv4Probing) {
        self.probe = probe
    }

    @discardableResult
    func refresh() -> Task<Void, Never> {
        let previous = status.info
        refreshTask?.cancel()
        let id = UUID()
        requestID = id
        lastRefreshStartedAt = clock.now
        status = .loading(previous: previous)

        let task = Task { [weak self, probe] in
            do {
                let info = try await probe.fetch()
                guard !Task.isCancelled,
                      let self,
                      self.requestID == id else { return }
                self.status = .available(info)
            } catch {
                guard !Task.isCancelled,
                      let self,
                      self.requestID == id else { return }
                self.status = .failed(
                    previous: previous,
                    reason: NetworkFailure.map(error)
                )
            }
        }
        refreshTask = task
        return task
    }

    /// 出口变化通知与网络事件往往在同一时刻到达；最近刚检测过或正在检测时不重复请求。
    func refreshIfStale(minimumInterval: Duration = .seconds(3)) {
        if status.isLoading { return }
        if let lastRefreshStartedAt,
           lastRefreshStartedAt.duration(to: clock.now) < minimumInterval { return }
        refresh()
    }

    func markOffline() {
        refreshTask?.cancel()
        refreshTask = nil
        requestID = nil
        status = .failed(previous: status.info, reason: .offline)
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        requestID = nil
    }
}
