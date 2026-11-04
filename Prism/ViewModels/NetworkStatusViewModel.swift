import AppKit
import Observation

@MainActor
@Observable
final class NetworkStatusViewModel {
    private(set) var status: NetworkStatus
    private let service: NetworkLookupService
    @ObservationIgnored private var observationTask: Task<Void, Never>?

    init(service: NetworkLookupService, initialStatus: NetworkStatus = .idle) {
        self.service = service
        self.status = initialStatus
    }

    func start() {
        observationTask?.cancel()
        observationTask = Task { [weak self, service] in
            for await status in service.stream() {
                guard let self else { return }
                let previous = self.status
                self.status = status
                announceIfNeeded(from: previous, to: status)
            }
        }
    }

    private func announceIfNeeded(from previous: NetworkStatus, to current: NetworkStatus) {
        let confirmed: NetworkInfo?
        switch current {
        case .online(let info), .locating(let info), .locationUnavailable(let info, _): confirmed = info
        default: confirmed = nil
        }
        let announcement: String?
        if let confirmed,
           previous.retainedInfo?.addresses.preferredForLookup != confirmed.addresses.preferredForLookup {
            let country = confirmed.hasLocation ? "\(confirmed.location.localizedCountry()) · " : ""
            announcement = "\(String(localized: "Network exit changed")): \(country)\(confirmed.addresses.preferredForLookup ?? "")"
        } else if case .verifying = current, !previous.isRefreshing {
            announcement = String(localized: "Confirming new exit")
        } else {
            announcement = nil
        }
        guard let announcement else { return }
        guard let application = NSApp else { return }
        NSAccessibility.post(
            element: application,
            notification: .announcementRequested,
            userInfo: [
                .announcement: announcement,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }
}
