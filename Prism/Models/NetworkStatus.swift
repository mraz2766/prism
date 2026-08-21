import Foundation

enum NetworkFailure: Error, Codable, Equatable, Sendable {
    case offline
    case timeout
    case serviceUnavailable
    case invalidResponse
    case cancelled
    case other

    var userDescription: String {
        switch self {
        case .offline: String(localized: "No internet connection")
        case .timeout: String(localized: "The request timed out")
        case .serviceUnavailable: String(localized: "Network information is temporarily unavailable")
        case .invalidResponse: String(localized: "The service returned an unexpected response")
        case .cancelled: String(localized: "The request was cancelled")
        case .other: String(localized: "Unable to update network information")
        }
    }

    static func map(_ error: Error) -> NetworkFailure {
        if let failure = error as? NetworkFailure { return failure }
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return .offline
            case .timedOut:
                return .timeout
            case .cancelled:
                return .cancelled
            default:
                return .serviceUnavailable
            }
        }
        return .other
    }
}

enum NetworkStatus: Equatable, Sendable {
    case idle
    case loading(previous: NetworkInfo?)
    case verifying(previous: NetworkInfo?, candidateAddress: String)
    case online(NetworkInfo)
    case offline(previous: NetworkInfo?)
    case stale(NetworkInfo, reason: NetworkFailure)
    case failed(NetworkFailure)

    var info: NetworkInfo? {
        switch self {
        case .loading(let previous), .verifying(let previous, _): previous
        case .online(let info), .stale(let info, _): info
        case .idle, .offline, .failed: nil
        }
    }

    var retainedInfo: NetworkInfo? {
        switch self {
        case .loading(let previous), .verifying(let previous, _), .offline(let previous): previous
        case .online(let info), .stale(let info, _): info
        case .idle, .failed: nil
        }
    }

    var isOffline: Bool {
        if case .offline = self { return true }
        return false
    }

    var isRefreshing: Bool {
        switch self {
        case .loading, .verifying: true
        default: false
        }
    }

    var shortLabel: String {
        switch self {
        case .online: String(localized: "Online")
        case .loading: String(localized: "Detecting")
        case .verifying: String(localized: "Confirming new exit")
        case .offline: String(localized: "Offline")
        case .stale: String(localized: "Update unavailable")
        case .failed, .idle: String(localized: "Unknown")
        }
    }

    var symbolName: String {
        switch self {
        case .online: "checkmark.circle.fill"
        case .loading, .verifying: "arrow.triangle.2.circlepath"
        case .offline: "wifi.slash"
        case .stale: "exclamationmark.circle.fill"
        case .failed, .idle: "questionmark.circle"
        }
    }
}
