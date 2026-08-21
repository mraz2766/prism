import Foundation

struct DomesticIPv4Info: Equatable, Sendable {
    let address: String
    let isChinese: Bool
    let checkedAt: Date

    func relationship(to currentIPv4: String?) -> DomesticExitRelationship {
        if let currentIPv4, currentIPv4 == address { return .sameAsCurrentExit }
        if isChinese { return currentIPv4 == nil ? .domesticObserved : .independentDomesticExit }
        return .possiblyProxied
    }
}

enum DomesticExitRelationship: Equatable, Sendable {
    case domesticObserved
    case independentDomesticExit
    case sameAsCurrentExit
    case possiblyProxied

    var label: String {
        switch self {
        case .domesticObserved: String(localized: "Chinese exit observed")
        case .independentDomesticExit: String(localized: "Independent domestic exit")
        case .sameAsCurrentExit: String(localized: "Same as current exit")
        case .possiblyProxied: String(localized: "Domestic traffic may still use the proxy")
        }
    }
}

enum DomesticIPv4Status: Equatable, Sendable {
    case idle
    case loading(previous: DomesticIPv4Info?)
    case available(DomesticIPv4Info)
    case failed(previous: DomesticIPv4Info?, reason: NetworkFailure)

    var info: DomesticIPv4Info? {
        switch self {
        case .loading(let previous), .failed(let previous, _): previous
        case .available(let info): info
        case .idle: nil
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    func matchesCurrentExit(_ currentIPv4: String?) -> Bool {
        guard case .available(let info) = self,
              let currentIPv4 else { return false }
        return info.address == currentIPv4
    }
}
