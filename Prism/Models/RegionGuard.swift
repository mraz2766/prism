import Foundation

/// 期望地区守护：出口国家不在用户指定的列表内时给出提醒。
struct RegionGuard: Equatable, Sendable {
    let isEnabled: Bool
    let expectedCodes: [String]

    init(isEnabled: Bool, expectedCountries: String) {
        self.isEnabled = isEnabled
        expectedCodes = Self.parse(expectedCountries)
    }

    /// 接受逗号、顿号、分号或空白分隔的两位 ISO 国家代码，忽略大小写与重复项。
    static func parse(_ raw: String) -> [String] {
        var seen: [String] = []
        let separators = CharacterSet(charactersIn: ",，、;；/|").union(.whitespacesAndNewlines)
        for token in raw.components(separatedBy: separators) {
            let code = token.uppercased()
            guard code.count == 2,
                  code.unicodeScalars.allSatisfy({ (65...90).contains($0.value) }),
                  !seen.contains(code) else { continue }
            seen.append(code)
        }
        return seen
    }

    var isActive: Bool { isEnabled && !expectedCodes.isEmpty }

    /// 国家尚未识别时不判定为越界，避免在归属地补全前误报。
    func isViolated(by countryCode: String) -> Bool {
        guard isActive else { return false }
        let code = countryCode.uppercased()
        guard !code.isEmpty else { return false }
        return !expectedCodes.contains(code)
    }

    func isViolated(by status: NetworkStatus) -> Bool {
        switch status {
        case .online(let info), .locating(let info), .locationUnavailable(let info, _):
            isViolated(by: info.location.countryCode)
        default:
            false
        }
    }
}
